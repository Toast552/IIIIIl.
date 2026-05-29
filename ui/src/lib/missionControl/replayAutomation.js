export const REPLAY_AUTOMATION_PREROLL_MS = 1200;
export const REPLAY_AUTOMATION_FAILURE_HOLD_MS = 1800;
export const REPLAY_AUTOMATION_TIMEOUT_MS = 45000;

export function nextReplayAutomationTransition(snapshot, progress, nowMs) {
  if (!progress.active) {
    return { ...progress, action: null, error: null };
  }

  if (nowMs - progress.startedAtMs > REPLAY_AUTOMATION_TIMEOUT_MS) {
    return {
      active: false,
      stage: 'idle',
      startedAtMs: progress.startedAtMs,
      recoverAfterMs: 0,
      action: null,
      error: 'Replay automation timed out before completion.',
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

  const recoverAfterMs = progress.recoverAfterMs || nowMs + REPLAY_AUTOMATION_FAILURE_HOLD_MS;
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
