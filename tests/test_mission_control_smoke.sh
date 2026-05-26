#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${NULLHUB_URL:-http://127.0.0.1:19802}"

node - "$BASE_URL" <<'NODE'
const base = process.argv[2];

async function api(path, method = 'GET') {
  const res = await fetch(base + path, { method });
  const text = await res.text();
  const body = text ? JSON.parse(text) : null;
  return { status: res.status, body };
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

let response = await api('/api/mission-control/reset', 'POST');
assert(response.status === 200, `reset returned ${response.status}`);
assert(response.body.schema_version === 1, 'missing schema_version');
assert(response.body.mode === 'deterministic_local_replay', 'unexpected mission mode');
assert(response.body.status === 'idle', `expected idle, got ${response.body.status}`);

response = await api('/api/mission-control/recover', 'POST');
assert(response.status === 409, `early recover returned ${response.status}`);
assert(response.body.error?.code === 'mission_not_recoverable', 'missing recover conflict code');

response = await api('/api/mission-control/launch', 'POST');
assert(response.status === 200, `launch returned ${response.status}`);
assert(response.body.status === 'running', `expected running, got ${response.body.status}`);

response = await api('/api/mission-control/launch', 'POST');
assert(response.status === 409, `duplicate launch returned ${response.status}`);
assert(response.body.error?.code === 'mission_already_started', 'missing launch conflict code');

await sleep(10_500);
response = await api('/api/mission-control/state');
assert(response.status === 200, `state returned ${response.status}`);
assert(response.body.status === 'intervention_required', `expected intervention_required, got ${response.body.status}`);
assert(response.body.controls.can_recover === true, 'expected recover control');
assert(response.body.failure?.run_id === 'run-mission-code-red-failed', 'missing failed replay failure panel');
assert(response.body.replay_comparison === null, 'replay comparison must not expose recovered artifact before recovery');
const failedEvent = response.body.events.find((event) => event.title === 'Validation failed');
assert(failedEvent?.trace?.run_id === 'run-mission-code-red-failed', 'missing failed run trace ref');
assert(failedEvent?.trace?.eval_key === 'tool_success', 'missing failed eval trace ref');

response = await api('/api/mission-control/recover', 'POST');
assert(response.status === 200, `recover returned ${response.status}`);
assert(response.body.recovered_run_id === 'run-mission-code-red-recovered', 'missing recovered run id');

await sleep(12_000);
response = await api('/api/mission-control/state');
assert(response.status === 200, `final state returned ${response.status}`);
assert(response.body.status === 'completed', `expected completed, got ${response.body.status}`);
assert(response.body.telemetry.verdict === 'pass', `expected pass verdict, got ${response.body.telemetry.verdict}`);
assert(response.body.replay_comparison?.recovered?.run_id === 'run-mission-code-red-recovered', 'missing recovered replay artifact comparison');
assert(response.body.replay_comparison?.delta?.checkpoint_reused === true, 'missing replay artifact checkpoint reuse');
const recoveredEvent = response.body.events.find((event) => event.title === 'Recovered tests passed');
assert(recoveredEvent?.trace?.run_id === 'run-mission-code-red-recovered', 'missing recovered run trace ref');
const finalState = response.body;

response = await api('/api/mission-control/replay');
assert(response.status === 200, `replay export returned ${response.status}`);
assert(response.body.artifact_kind === 'nullhub.mission_control.replay', 'unexpected replay artifact kind');
assert(response.body.snapshot?.status === 'completed', 'replay export missing completed snapshot');
assert(response.body.snapshot?.replay_comparison?.recovered?.verdict === 'pass', 'replay export missing recovered artifact comparison');
assert(response.body.replay_fixture?.scenario_id === 'mission-code-red', 'replay export missing source fixture');
assert(response.body.ecosystem_mapping?.nullwatch?.trace_ref_source === 'events[].trace', 'replay export missing nullwatch mapping');

response = await api('/api/mission-control/replay/save', 'POST');
assert(response.status === 200, `replay save returned ${response.status}`);
const savedReplayId = response.body.record?.id;
assert(savedReplayId, 'replay save missing durable record id');
assert(response.body.record?.phase === 'completed', 'replay save missing completed phase');

response = await api('/api/mission-control/replays');
assert(response.status === 200, `replay list returned ${response.status}`);
assert(response.body.items?.some((item) => item.id === savedReplayId), 'saved replay not listed');

response = await api(`/api/mission-control/replays/${encodeURIComponent(savedReplayId)}`);
assert(response.status === 200, `stored replay read returned ${response.status}`);
assert(response.body.artifact_kind === 'nullhub.mission_control.replay', 'stored replay missing artifact kind');
assert(response.body.snapshot?.phase === 'completed', 'stored replay missing completed snapshot');

console.log(`mission-control smoke ok: ${finalState.status}, ${finalState.telemetry.spans} spans, ${finalState.telemetry.evals} evals`);
NODE
