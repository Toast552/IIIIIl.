import type { MissionControlState } from '$lib/api/missionControl';

type NullWatchTarget = {
  watch?: string;
};

type TraceHydrationApi = {
  getStatus: () => Promise<StatusPayload>;
  getNullWatchRuns: (
    params?: NullWatchTarget & { run_id?: string; limit?: number },
  ) => Promise<NullWatchRunsPayload>;
  getNullWatchRun: (
    runId: string,
    params?: NullWatchTarget,
  ) => Promise<NullWatchRunDetail>;
};

export type NullWatchRunSummary = {
  run_id?: string;
  span_count?: number;
  eval_count?: number;
  error_count?: number;
  total_input_tokens?: number;
  total_output_tokens?: number;
  total_cost_usd?: number;
  total_duration_ms?: number;
  overall_verdict?: string;
};

export type NullWatchSpan = {
  operation?: string;
  status?: string;
  source?: string;
  duration_ms?: number;
  error_message?: string;
  tool_name?: string;
};

export type NullWatchEval = {
  eval_key?: string;
  verdict?: string;
  score?: number;
  scorer?: string;
  dataset?: string;
  notes?: string;
};

export type TraceHydrationStatus = 'available' | 'unavailable';
export type TraceHydrationUnavailableReason =
  | 'no_running_nullwatch'
  | 'status_unavailable'
  | 'run_not_found'
  | 'nullwatch_unavailable'
  | 'run_detail_unavailable'
  | 'empty_run_detail';

export type TraceHydration = {
  runId: string;
  status: TraceHydrationStatus;
  unavailableReason?: TraceHydrationUnavailableReason;
  message?: string;
  summary: NullWatchRunSummary | null;
  spans: NullWatchSpan[];
  evals: NullWatchEval[];
  loadedAtMs: number;
};

type NullWatchOption = {
  name: string;
  status: string;
};

export type NullWatchSelection = {
  watch: string | null;
  unavailableReason?: TraceHydrationUnavailableReason;
  message?: string;
};

type StatusPayload = {
  instances?: {
    nullwatch?: Record<string, { status?: string }>;
  };
};

type NullWatchRunsPayload = {
  items?: Array<{ run_id?: string }>;
};

type NullWatchRunDetail = {
  summary?: NullWatchRunSummary;
  run?: NullWatchRunSummary;
  spans?: NullWatchSpan[];
  evals?: NullWatchEval[];
};

export async function findRunningNullWatch(api: TraceHydrationApi): Promise<NullWatchSelection> {
  try {
    const status = await api.getStatus();
    const watch = runningTraceWatchName(status);
    if (watch) return { watch };
    return {
      watch: null,
      unavailableReason: 'no_running_nullwatch',
      message: unavailableTraceMessage('no_running_nullwatch'),
    };
  } catch {
    return {
      watch: null,
      unavailableReason: 'status_unavailable',
      message: unavailableTraceMessage('status_unavailable'),
    };
  }
}

export async function hydrateMissionTracePanels(
  api: TraceHydrationApi,
  snapshot: MissionControlState,
  watch: string | null,
  unavailableReason: TraceHydrationUnavailableReason = 'no_running_nullwatch',
): Promise<Record<string, TraceHydration>> {
  const runIds = missionTracePanelRunIds(snapshot);
  if (runIds.length === 0) return {};
  if (!watch) {
    return Object.fromEntries(
      runIds.map((runId) => [
        runId,
        unavailableTrace(runId, unavailableReason),
      ]),
    );
  }

  const entries = await Promise.all(runIds.map((runId) => loadTraceHydration(api, runId, watch)));
  return Object.fromEntries(entries.map((entry) => [entry.runId, entry]));
}

export function isAvailableTrace(trace: TraceHydration | null | undefined): trace is TraceHydration {
  return trace?.status === 'available';
}

function runningTraceWatchName(status: StatusPayload): string | null {
  const watches = extractNullWatchOptions(status);
  const running = watches.find((watch) => watch.status === 'running');
  return running?.name || null;
}

function extractNullWatchOptions(status: StatusPayload): NullWatchOption[] {
  const instances = status?.instances?.nullwatch || {};
  return Object.entries(instances).map(([name, info]) => ({
    name,
    status: info?.status || 'stopped',
  }));
}

async function loadTraceHydration(
  api: TraceHydrationApi,
  runId: string,
  watch: string,
): Promise<TraceHydration> {
  let listed: NullWatchRunsPayload;
  try {
    listed = await api.getNullWatchRuns({ run_id: runId, limit: 1, watch });
  } catch {
    return unavailableTrace(runId, 'nullwatch_unavailable');
  }

  const found = Array.isArray(listed?.items) && listed.items.some((item) => item?.run_id === runId);
  if (!found) return unavailableTrace(runId, 'run_not_found');

  try {
    const detail = await api.getNullWatchRun(runId, { watch });
    const summary = normalizeRunSummary(detail, runId);
    const spans = Array.isArray(detail?.spans) ? detail.spans : [];
    const evals = Array.isArray(detail?.evals) ? detail.evals : [];
    if (!summary && spans.length === 0 && evals.length === 0) return unavailableTrace(runId, 'empty_run_detail');
    return {
      runId,
      status: 'available',
      summary,
      spans,
      evals,
      loadedAtMs: Date.now(),
    };
  } catch {
    return unavailableTrace(runId, 'run_detail_unavailable');
  }
}

function unavailableTrace(runId: string, reason: TraceHydrationUnavailableReason): TraceHydration {
  return {
    runId,
    status: 'unavailable',
    unavailableReason: reason,
    message: unavailableTraceMessage(reason),
    summary: null,
    spans: [],
    evals: [],
    loadedAtMs: Date.now(),
  };
}

function unavailableTraceMessage(reason: TraceHydrationUnavailableReason): string {
  if (reason === 'no_running_nullwatch') return 'No running NullWatch instance';
  if (reason === 'status_unavailable') return 'NullHub status unavailable';
  if (reason === 'run_not_found') return 'No matching live run';
  if (reason === 'nullwatch_unavailable') return 'NullWatch run list unavailable';
  if (reason === 'run_detail_unavailable') return 'NullWatch run detail unavailable';
  return 'NullWatch returned no run detail';
}

export function missionTracePanelRunIds(snapshot: MissionControlState): string[] {
  const ids: string[] = [];
  addRunId(ids, snapshot.failure?.run_id || snapshot.failed_run_id);
  addRunId(ids, snapshot.recovery?.run_id || snapshot.recovered_run_id);
  return ids;
}

function addRunId(ids: string[], runId: string | null | undefined) {
  if (runId && !ids.includes(runId)) ids.push(runId);
}

function normalizeRunSummary(detail: NullWatchRunDetail, runId: string): NullWatchRunSummary | null {
  const summary = detail?.summary || detail?.run || null;
  if (!summary || typeof summary !== 'object') return null;
  return {
    ...summary,
    run_id: summary.run_id || runId,
  };
}
