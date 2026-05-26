export const JUDGE_REPLAY_PREROLL_MS = 1200;
export const JUDGE_REPLAY_FAILURE_HOLD_MS = 1800;
export const JUDGE_REPLAY_TIMEOUT_MS = 45000;

export function nextJudgeReplayTransition(snapshot, progress, nowMs) {
  if (!progress.active) {
    return { ...progress, action: null, error: null };
  }

  if (nowMs - progress.startedAtMs > JUDGE_REPLAY_TIMEOUT_MS) {
    return {
      active: false,
      stage: 'idle',
      startedAtMs: progress.startedAtMs,
      recoverAfterMs: 0,
      action: null,
      error: 'Judge replay timed out before completion.',
    };
  }

  if (snapshot.status === 'completed') {
    return {
      active: false,
      stage: 'idle',
      startedAtMs: progress.startedAtMs,
      recoverAfterMs: 0,
      action: null,
      error: null,
    };
  }

  if (snapshot.recovery) {
    return {
      ...progress,
      stage: 'watching',
      action: null,
      error: null,
    };
  }

  if (!snapshot.controls?.can_recover) {
    return {
      ...progress,
      stage: 'waiting_failure',
      action: null,
      error: null,
    };
  }

  const recoverAfterMs = progress.recoverAfterMs || nowMs + JUDGE_REPLAY_FAILURE_HOLD_MS;
  if (nowMs < recoverAfterMs) {
    return {
      ...progress,
      stage: 'holding_failure',
      recoverAfterMs,
      action: null,
      error: null,
    };
  }

  return {
    ...progress,
    stage: 'recovering',
    recoverAfterMs,
    action: 'recover',
    error: null,
  };
}
