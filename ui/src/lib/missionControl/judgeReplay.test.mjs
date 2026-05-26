import assert from 'node:assert/strict';
import {
  JUDGE_REPLAY_FAILURE_HOLD_MS,
  JUDGE_REPLAY_TIMEOUT_MS,
  nextJudgeReplayTransition,
} from './judgeReplay.js';

const baseProgress = {
  active: true,
  stage: 'waiting_failure',
  startedAtMs: 1000,
  recoverAfterMs: 0,
};

const waiting = nextJudgeReplayTransition(
  { status: 'running', controls: { can_recover: false } },
  baseProgress,
  2000,
);
assert.equal(waiting.stage, 'waiting_failure');
assert.equal(waiting.action, null);

const holding = nextJudgeReplayTransition(
  { status: 'intervention_required', controls: { can_recover: true } },
  baseProgress,
  3000,
);
assert.equal(holding.stage, 'holding_failure');
assert.equal(holding.recoverAfterMs, 3000 + JUDGE_REPLAY_FAILURE_HOLD_MS);
assert.equal(holding.action, null);

const recovering = nextJudgeReplayTransition(
  { status: 'intervention_required', controls: { can_recover: true } },
  { ...holding, recoverAfterMs: 3000 },
  3000,
);
assert.equal(recovering.stage, 'recovering');
assert.equal(recovering.action, 'recover');

const completed = nextJudgeReplayTransition(
  { status: 'completed', controls: { can_recover: false } },
  baseProgress,
  4000,
);
assert.equal(completed.active, false);
assert.equal(completed.stage, 'idle');

const timedOut = nextJudgeReplayTransition(
  { status: 'running', controls: { can_recover: false } },
  baseProgress,
  1000 + JUDGE_REPLAY_TIMEOUT_MS + 1,
);
assert.equal(timedOut.active, false);
assert.equal(timedOut.stage, 'idle');
assert.match(timedOut.error, /timed out/);
