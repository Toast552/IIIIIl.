import type { MissionControlState } from '$lib/api/missionControl';

type ObservabilityTarget = {
  watch?: string;
};

type TraceHydrationApi = {
  getStatus: () => Promise<StatusPayload>;
  getObservabilityRuns: (
    params?: ObservabilityTarget & { run_id?: string; limit?: number },
  ) => Promise<ObservabilityRunsPayload>;
  getObservabilityRun: (
    runId: string,
    params?: ObservabilityTarget,
  ) => Promise<ObservabilityRunDetail>;
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

export type TraceHydration = {
  runId: string;
  summary: NullWatchRunSummary | null;
  spans: NullWatchSpan[];
  evals: NullWatchEval[];
  loadedAtMs: number;
};

type NullWatchOption = {
  name: string;
  status: string;
};

type StatusPayload = {
  instances?: {
    nullwatch?: Record<string, { status?: string }>;
  };
};

type ObservabilityRunsPayload = {
  items?: Array<{ run_id?: string }>;
};

type ObservabilityRunDetail = {
  summary?: NullWatchRunSummary;
  run?: NullWatchRunSummary;
  spans?: NullWatchSpan[];
  evals?: NullWatchEval[];
};

export async function findRunningNullWatchName(api: TraceHydrationApi): Promise<string | null> {
  try {
    const status = await api.getStatus();
    return runningTraceWatchName(status);
  } catch {
    return null;
  }
}

export async function hydrateMissionTracePanels(
  api: TraceHydrationApi,
  snapshot: MissionControlState,
  watch: string | null,
): Promise<Record<string, TraceHydration>> {
  const runIds = missionTracePanelRunIds(snapshot);
  if (runIds.length === 0 || !watch) return {};

  const entries = await Promise.all(runIds.map((runId) => loadTraceHydration(api, runId, watch)));
  return Object.fromEntries(
    entries.filter((entry): entry is TraceHydration => Boolean(entry)).map((entry) => [entry.runId, entry]),
  );
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
): Promise<TraceHydration | null> {
  try {
    const listed = await api.getObservabilityRuns({ run_id: runId, limit: 1, watch });
    const found = Array.isArray(listed?.items) && listed.items.some((item) => item?.run_id === runId);
    if (!found) return null;

    const detail = await api.getObservabilityRun(runId, { watch });
    const summary = normalizeRunSummary(detail, runId);
    const spans = Array.isArray(detail?.spans) ? detail.spans : [];
    const evals = Array.isArray(detail?.evals) ? detail.evals : [];
    if (!summary && spans.length === 0 && evals.length === 0) return null;
    return {
      runId,
      summary,
      spans,
      evals,
      loadedAtMs: Date.now(),
    };
  } catch {
    return null;
  }
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

function normalizeRunSummary(detail: ObservabilityRunDetail, runId: string): NullWatchRunSummary | null {
  const summary = detail?.summary || detail?.run || null;
  if (!summary || typeof summary !== 'object') return null;
  return {
    ...summary,
    run_id: summary.run_id || runId,
  };
}
