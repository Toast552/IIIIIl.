import { orchestrationApiPaths } from '$lib/orchestration/routes';
import { getSelectedBoilerInstance } from '$lib/orchestration/backendSelection';

type RequestFn = <T>(path: string, options?: RequestInit) => Promise<T>;
type WithQueryFn = (
  path: string,
  params: Record<string, string | number | boolean | null | undefined>,
) => string;
type QueryParams = Record<string, string | number | boolean | null | undefined>;
type BoilerOptions = { boilerInstance?: string };
type RunListParams = {
  status?: string;
  workflow_id?: string;
  limit?: number;
  offset?: number;
  boilerInstance?: string;
};

export type RunListPage = {
  items: any[];
  limit?: number;
  offset?: number;
  nextOffset?: number;
  hasMore: boolean;
};

export type RunStreamHandle = {
  close: () => void;
  readonly closed: boolean;
};

const orchestrationStorePrefix = '/orchestration/store';

function msToIso(ms: number | undefined | null): string | undefined {
  if (ms == null) return undefined;
  return new Date(ms).toISOString();
}

function tryParseJson(val: string | undefined | null): any {
  if (!val) return undefined;
  try { return JSON.parse(val); } catch { return val; }
}

function normalizeWorkflow(raw: any): any {
  if (!raw) return raw;
  const def = raw.definition ? tryParseJson(raw.definition) : null;
  return {
    ...raw,
    nodes: raw.nodes ?? def?.nodes ?? {},
    edges: raw.edges ?? def?.edges ?? [],
    state_schema: raw.state_schema ?? def?.state_schema,
    created_at: raw.created_at ?? msToIso(raw.created_at_ms),
    updated_at: raw.updated_at ?? msToIso(raw.updated_at_ms),
  };
}

function normalizeStep(step: any): any {
  if (!step) return step;
  return {
    ...step,
    node_id: step.node_id ?? step.def_step_id ?? step.step,
  };
}

function normalizeRun(raw: any): any {
  if (!raw) return raw;
  const steps = raw.steps ? raw.steps.map(normalizeStep) : raw.steps;
  return {
    ...raw,
    steps,
    state: raw.state ?? tryParseJson(raw.state_json),
    workflow: raw.workflow ?? tryParseJson(raw.workflow_json),
    input: raw.input ?? tryParseJson(raw.input_json),
    config: raw.config ?? tryParseJson(raw.config_json),
    created_at: raw.created_at ?? msToIso(raw.created_at_ms),
    completed_at: raw.completed_at ?? raw.ended_at ?? msToIso(raw.ended_at_ms),
    updated_at: raw.updated_at ?? msToIso(raw.updated_at_ms),
    started_at: raw.started_at ?? msToIso(raw.started_at_ms),
    interrupt_message: raw.interrupt_message ?? raw.error_text,
  };
}

function normalizeRunListPage(raw: any): RunListPage {
  const list = Array.isArray(raw) ? raw : raw?.items ?? raw?.runs ?? [];
  return {
    items: (list || []).map(normalizeRun),
    limit: typeof raw?.limit === 'number' ? raw.limit : undefined,
    offset: typeof raw?.offset === 'number' ? raw.offset : undefined,
    nextOffset: typeof raw?.next_offset === 'number'
      ? raw.next_offset
      : typeof raw?.nextOffset === 'number'
        ? raw.nextOffset
        : undefined,
    hasMore: Boolean(raw?.has_more ?? raw?.hasMore),
  };
}

function normalizeCheckpoint(raw: any): any {
  if (!raw) return raw;
  return {
    ...raw,
    state: raw.state ?? tryParseJson(raw.state_json),
    completed_nodes: raw.completed_nodes ?? tryParseJson(raw.completed_nodes_json),
    metadata: raw.metadata ?? tryParseJson(raw.metadata_json),
    created_at: raw.created_at ?? msToIso(raw.created_at_ms),
    step_name: raw.step_name ?? raw.step_id,
    after_step: raw.after_step ?? raw.step_id,
  };
}

function normalizeValidation(raw: any): any {
  if (!raw) return raw;
  if (raw.errors && Array.isArray(raw.errors) && raw.errors.length > 0 && typeof raw.errors[0] === 'object') {
    return { ...raw, errors: raw.errors.map((e: any) => e.message || `${e.type || e.err_type}: ${e.key || e.node || 'unknown'}`) };
  }
  return raw;
}

function normalizeEventType(type: string | undefined): string {
  if (!type) return 'message';
  if (type === 'run.interrupted') return 'interrupted';
  return type.replaceAll('.', '_');
}

function normalizeStreamEvent(raw: any): { type: string; data: any; timestamp?: number } {
  const timestampMs = typeof raw?.ts_ms === 'number'
    ? raw.ts_ms
    : typeof raw?.timestamp_ms === 'number'
      ? raw.timestamp_ms
      : undefined;

  return {
    type: normalizeEventType(raw?.event || raw?.type || raw?.kind),
    data: raw?.data ?? raw,
    timestamp: timestampMs != null ? timestampMs / 1000 : undefined,
  };
}

export function createOrchestrationApi(request: RequestFn, withQuery: WithQueryFn) {
  function withBoilerQuery(path: string, params: QueryParams = {}, boilerInstance?: string) {
    const selectedBoiler = path.startsWith(orchestrationStorePrefix)
      ? ''
      : boilerInstance ?? getSelectedBoilerInstance();
    return withQuery(path, { ...params, boiler_instance: selectedBoiler || undefined });
  }

  async function listRunsPage(params?: RunListParams): Promise<RunListPage> {
    const { boilerInstance, ...query } = params ?? {};
    const raw = await request<any>(withBoilerQuery(orchestrationApiPaths.runs(), query, boilerInstance));
    return normalizeRunListPage(raw);
  }

  return {
    listWorkflows: async (options?: BoilerOptions) => {
      const raw = await request<any>(withBoilerQuery(orchestrationApiPaths.workflows(), {}, options?.boilerInstance));
      const list = Array.isArray(raw) ? raw : raw?.items ?? [];
      return list.map(normalizeWorkflow);
    },
    getWorkflow: async (id: string, options?: BoilerOptions) =>
      normalizeWorkflow(await request<any>(withBoilerQuery(orchestrationApiPaths.workflow(id), {}, options?.boilerInstance))),
    createWorkflow: (data: any, options?: BoilerOptions) =>
      request<any>(withBoilerQuery(orchestrationApiPaths.workflows(), {}, options?.boilerInstance), { method: 'POST', body: JSON.stringify(data) }),
    updateWorkflow: (id: string, data: any, options?: BoilerOptions) =>
      request<any>(withBoilerQuery(orchestrationApiPaths.workflow(id), {}, options?.boilerInstance), { method: 'PUT', body: JSON.stringify(data) }),
    deleteWorkflow: (id: string, options?: BoilerOptions) =>
      request<any>(withBoilerQuery(orchestrationApiPaths.workflow(id), {}, options?.boilerInstance), { method: 'DELETE' }),
    validateWorkflow: async (id: string, options?: BoilerOptions) =>
      normalizeValidation(await request<any>(withBoilerQuery(orchestrationApiPaths.workflowValidate(id), {}, options?.boilerInstance), { method: 'POST' })),
    runWorkflow: (id: string, input: any, options?: BoilerOptions) =>
      request<any>(withBoilerQuery(orchestrationApiPaths.workflowRun(id), {}, options?.boilerInstance), { method: 'POST', body: JSON.stringify(input) }),
    listRunsPage,
    listRuns: async (params?: RunListParams) => (await listRunsPage(params)).items,
    getRun: async (id: string, options?: BoilerOptions) =>
      normalizeRun(await request<any>(withBoilerQuery(orchestrationApiPaths.run(id), {}, options?.boilerInstance))),
    cancelRun: (id: string, options?: BoilerOptions) =>
      request<any>(withBoilerQuery(orchestrationApiPaths.runCancel(id), {}, options?.boilerInstance), { method: 'POST' }),
    retryRun: (id: string, options?: BoilerOptions) =>
      request<any>(withBoilerQuery(orchestrationApiPaths.runRetry(id), {}, options?.boilerInstance), { method: 'POST' }),
    resumeRun: (id: string, updates: any, options?: BoilerOptions) =>
      request<any>(withBoilerQuery(orchestrationApiPaths.runResume(id), {}, options?.boilerInstance), { method: 'POST', body: JSON.stringify({ state_updates: updates }) }),
    forkRun: (checkpointId: string, overrides?: any, options?: BoilerOptions) =>
      request<any>(withBoilerQuery(orchestrationApiPaths.runsFork(), {}, options?.boilerInstance), { method: 'POST', body: JSON.stringify({ checkpoint_id: checkpointId, state_overrides: overrides }) }),
    replayRun: (id: string, checkpointId: string, options?: BoilerOptions) =>
      request<any>(withBoilerQuery(orchestrationApiPaths.runReplay(id), {}, options?.boilerInstance), { method: 'POST', body: JSON.stringify({ from_checkpoint_id: checkpointId }) }),
    injectState: (id: string, updates: any, afterStep?: string, options?: BoilerOptions) =>
      request<any>(withBoilerQuery(orchestrationApiPaths.runState(id), {}, options?.boilerInstance), { method: 'POST', body: JSON.stringify({ updates, apply_after_step: afterStep }) }),
    listCheckpoints: async (runId: string, options?: BoilerOptions) => {
      const cps = await request<any[]>(withBoilerQuery(orchestrationApiPaths.runCheckpoints(runId), {}, options?.boilerInstance));
      return (cps || []).map(normalizeCheckpoint);
    },
    getCheckpoint: async (runId: string, cpId: string, options?: BoilerOptions) =>
      normalizeCheckpoint(await request<any>(withBoilerQuery(orchestrationApiPaths.runCheckpoint(runId, cpId), {}, options?.boilerInstance))),
    getBoilerTrackerStatus: (options?: BoilerOptions) =>
      request<any>(withBoilerQuery(orchestrationApiPaths.trackerStatus(), {}, options?.boilerInstance)),
    getBoilerTrackerTasks: (options?: BoilerOptions) =>
      request<any>(withBoilerQuery(orchestrationApiPaths.trackerTasks(), {}, options?.boilerInstance)),
    getBoilerTrackerStats: (options?: BoilerOptions) =>
      request<any>(withBoilerQuery(orchestrationApiPaths.trackerStats(), {}, options?.boilerInstance)),
    refreshBoilerTracker: (options?: BoilerOptions) =>
      request<any>(withBoilerQuery(orchestrationApiPaths.trackerRefresh(), {}, options?.boilerInstance), { method: 'POST' }),
    listWorkers: (options?: BoilerOptions) =>
      request<any[]>(withBoilerQuery(orchestrationApiPaths.workers(), {}, options?.boilerInstance)),
    registerWorker: (data: any, options?: BoilerOptions) =>
      request<any>(withBoilerQuery(orchestrationApiPaths.workers(), {}, options?.boilerInstance), { method: 'POST', body: JSON.stringify(data) }),
    deleteWorker: (id: string, options?: BoilerOptions) =>
      request<any>(withBoilerQuery(orchestrationApiPaths.worker(id), {}, options?.boilerInstance), { method: 'DELETE' }),
    storeList: (namespace: string, ticketsInstance?: string) =>
      request<any[]>(withQuery(orchestrationApiPaths.storeNamespace(namespace), { tickets_instance: ticketsInstance })),
    storeGet: (namespace: string, key: string, ticketsInstance?: string) =>
      request<any>(withQuery(orchestrationApiPaths.storeEntry(namespace, key), { tickets_instance: ticketsInstance })),
    storePut: (namespace: string, key: string, value: any, ticketsInstance?: string) =>
      request<void>(withQuery(orchestrationApiPaths.storeEntry(namespace, key), { tickets_instance: ticketsInstance }), { method: 'PUT', body: JSON.stringify({ value }) }),
    storeDelete: (namespace: string, key: string, ticketsInstance?: string) =>
      request<void>(withQuery(orchestrationApiPaths.storeEntry(namespace, key), { tickets_instance: ticketsInstance }), { method: 'DELETE' }),
    streamRun: (
      runId: string,
      onEvent: (event: { type: string; data: any; timestamp?: number }) => void,
      options?: BoilerOptions,
    ) => {
      let active = true;
      let closed = false;
      let deliveredInitialSnapshot = false;
      let afterSeq = 0;

      const emitEvent = (ev: any) => {
        if (!active) return;
        onEvent(normalizeStreamEvent(ev));
      };

      const poll = async () => {
        while (active) {
          try {
            const res = await request<any>(withBoilerQuery(orchestrationApiPaths.runStream(runId), {
              after_seq: afterSeq > 0 ? afterSeq : undefined,
            }, options?.boilerInstance));
            if (!active) break;
            if (res?.stream_events) {
              for (const ev of res.stream_events) emitEvent(ev);
            }
            if (!deliveredInitialSnapshot && res?.events) {
              for (const ev of res.events) emitEvent(ev);
              deliveredInitialSnapshot = true;
            }
            if (typeof res?.next_stream_seq === 'number') {
              afterSeq = Math.max(afterSeq, res.next_stream_seq);
            }
            if (res?.status && ['completed', 'failed', 'cancelled'].includes(res.status)) {
              active = false;
              break;
            }
          } catch {
            if (!active) break;
            // Ignore poll errors, will retry.
          }
          if (!active) break;
          await new Promise(r => setTimeout(r, 1000));
        }
        closed = true;
      };

      void poll();
      return {
        close: () => {
          active = false;
          closed = true;
        },
        get closed() {
          return closed;
        },
      };
    },
  };
}
