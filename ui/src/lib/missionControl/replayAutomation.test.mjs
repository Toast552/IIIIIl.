import assert from 'node:assert/strict';
import {
  REPLAY_AUTOMATION_FAILURE_HOLD_MS,
  REPLAY_AUTOMATION_TIMEOUT_MS,
  nextReplayAutomationTransition,
} from './replayAutomation.js';

const baseProgress = {
  active: true,
  stage: 'waiting_failure',
  startedAtMs: 1000,
  recoverAfterMs: 0,
};

const waiting = nextReplayAutomationTransition(
  { status: 'running', controls: { can_recover: false } },
  baseProgress,
  2000,
);
assert.equal(waiting.stage, 'waiting_failure');
assert.equal(waiting.action, null);

const holding = nextReplayAutomationTransition(
  { status: 'intervention_required', controls: { can_recover: true } },
  baseProgress,
  3000,
);
assert.equal(holding.stage, 'holding_failure');
assert.equal(holding.recoverAfterMs, 3000 + REPLAY_AUTOMATION_FAILURE_HOLD_MS);
assert.equal(holding.action, null);

const recovering = nextReplayAutomationTransition(
  { status: 'intervention_required', controls: { can_recover: true } },
  { ...holding, recoverAfterMs: 3000 },
  3000,
);
assert.equal(recovering.stage, 'recovering');
assert.equal(recovering.action, 'recover');

const completed = nextReplayAutomationTransition(
  { status: 'completed', controls: { can_recover: false } },
  baseProgress,
  4000,
);
assert.equal(completed.active, false);
assert.equal(completed.stage, 'idle');

const timedOut = nextReplayAutomationTransition(
  { status: 'running', controls: { can_recover: false } },
  baseProgress,
  1000 + REPLAY_AUTOMATION_TIMEOUT_MS + 1,
);
assert.equal(timedOut.active, false);
assert.equal(timedOut.stage, 'idle');
assert.match(timedOut.error, /timed out/);
