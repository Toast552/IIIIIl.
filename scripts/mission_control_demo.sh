#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${NULLHUB_URL:-http://127.0.0.1:19802}"
OPEN_BROWSER="${MISSION_CONTROL_OPEN_BROWSER:-0}"
PREROLL_MS="${MISSION_CONTROL_PREROLL_MS:-1200}"
FAILURE_HOLD_MS="${MISSION_CONTROL_FAILURE_HOLD_MS:-1800}"
COMPLETION_HOLD_MS="${MISSION_CONTROL_COMPLETION_HOLD_MS:-1200}"
POLL_MS="${MISSION_CONTROL_POLL_MS:-500}"
TIMEOUT_MS="${MISSION_CONTROL_TIMEOUT_MS:-45000}"

node - "$BASE_URL" "$OPEN_BROWSER" "$PREROLL_MS" "$FAILURE_HOLD_MS" "$COMPLETION_HOLD_MS" "$POLL_MS" "$TIMEOUT_MS" <<'NODE'
const { spawn } = await import('node:child_process');

const base = process.argv[2].replace(/\/$/, '');
const openBrowser = process.argv[3] === '1';
const prerollMs = Number(process.argv[4]);
const failureHoldMs = Number(process.argv[5]);
const completionHoldMs = Number(process.argv[6]);
const pollMs = Number(process.argv[7]);
const timeoutMs = Number(process.argv[8]);
const missionUrl = `${base}/mission-control`;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function api(path, method = 'GET') {
  let res;
  try {
    res = await fetch(`${base}${path}`, { method });
  } catch (error) {
    throw new Error(`Cannot reach NullHub at ${base}: ${error.message}`);
  }

  const text = await res.text();
  const body = text ? JSON.parse(text) : null;
  return { status: res.status, body };
}

function openMissionPage() {
  const command =
    process.platform === 'darwin'
      ? 'open'
      : process.platform === 'win32'
        ? 'cmd'
        : 'xdg-open';
  const args = process.platform === 'win32' ? ['/c', 'start', '', missionUrl] : [missionUrl];
  const child = spawn(command, args, { detached: true, stdio: 'ignore' });
  child.unref();
}

function formatState(state) {
  return [
    `phase=${state.phase}`,
    `status=${state.status}`,
    `progress=${state.progress}%`,
    `run=${state.active_run_id || '-'}`,
    `spans=${state.telemetry?.spans ?? 0}`,
    `evals=${state.telemetry?.evals ?? 0}`,
    `verdict=${state.telemetry?.verdict || '-'}`,
  ].join(' ');
}

function printStep(label, state) {
  console.log(`${label.padEnd(12)} ${formatState(state)}`);
}

async function expectOk(path, method) {
  const response = await api(path, method);
  assert(response.status === 200, `${method} ${path} returned HTTP ${response.status}`);
  return response.body;
}

async function waitFor(label, predicate) {
  const started = Date.now();
  let lastPhase = '';
  let lastState = null;

  while (Date.now() - started < timeoutMs) {
    const response = await api('/api/mission-control/state');
    assert(response.status === 200, `state returned HTTP ${response.status}`);
    lastState = response.body;

    if (lastState.phase !== lastPhase) {
      printStep(label, lastState);
      lastPhase = lastState.phase;
    }

    if (predicate(lastState)) return lastState;
    await sleep(pollMs);
  }

  throw new Error(`Timed out waiting for ${label}. Last state: ${lastState ? formatState(lastState) : 'none'}`);
}

console.log('NullOS Mission Control judge demo');
console.log(`Base URL: ${base}`);
console.log(`Open UI:  ${missionUrl}`);

let state = await expectOk('/api/mission-control/reset', 'POST');
assert(state.schema_version === 1, 'unexpected mission schema version');
assert(state.mode === 'deterministic_local_replay', 'unexpected mission mode');
printStep('reset', state);

if (openBrowser) {
  openMissionPage();
  console.log('browser      opened mission-control page');
}

await sleep(prerollMs);

state = await expectOk('/api/mission-control/launch', 'POST');
printStep('launch', state);

state = await waitFor('primary', (candidate) => candidate.status === 'intervention_required' && candidate.controls?.can_recover === true);
const failedEvent = state.events?.find((event) => event.title === 'Validation failed');
assert(failedEvent?.trace?.run_id === 'run-demo-failed-test', 'missing failed run trace reference');
assert(failedEvent?.trace?.eval_key === 'tool_success', 'missing failed eval trace reference');
console.log('failure     human intervention point reached');

await sleep(failureHoldMs);

state = await expectOk('/api/mission-control/recover', 'POST');
assert(state.recovered_run_id === 'run-demo-recovered-fork', 'missing recovered run id');
printStep('recover', state);

state = await waitFor('recovery', (candidate) => candidate.status === 'completed' && candidate.telemetry?.verdict === 'pass');
const recoveredEvent = state.events?.find((event) => event.title === 'Recovered tests passed');
assert(recoveredEvent?.trace?.run_id === 'run-demo-recovered-fork', 'missing recovered run trace reference');

await sleep(completionHoldMs);

const artifactResponse = await api('/api/mission-control/replay');
assert(artifactResponse.status === 200, `replay export returned HTTP ${artifactResponse.status}`);
assert(artifactResponse.body?.artifact_kind === 'nullhub.mission_control.replay', 'unexpected replay artifact kind');
assert(artifactResponse.body?.snapshot?.status === 'completed', 'replay export did not capture completed snapshot');

console.log('completed    recovered mission passed');
console.log(`failed run:  ${state.failed_run_id}`);
console.log(`recovered:   ${state.recovered_run_id}`);
console.log(`trace link:  ${base}/nullwatch?run_id=${encodeURIComponent(state.recovered_run_id)}`);
console.log(`export:      ${base}/api/mission-control/replay`);
NODE
