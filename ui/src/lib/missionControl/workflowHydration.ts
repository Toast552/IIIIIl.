import type { MissionControlState } from '$lib/api/missionControl';

type BoilerOptions = {
  boilerInstance?: string;
};

type WorkflowHydrationApi = {
  listRunsPage: (params?: { limit?: number; offset?: number; boilerInstance?: string }) => Promise<RunListPage>;
  getRun: (id: string, options?: BoilerOptions) => Promise<unknown>;
  listCheckpoints: (runId: string, options?: BoilerOptions) => Promise<unknown[]>;
};

type RunListPage = {
  items?: unknown[];
};

type MissionWorkflowRefs = {
  scenarioId: string;
  missionId: string;
  failedRunId: string;
  recoveredRunId: string;
  checkpointId: string;
};

type RunCandidate = NullBoilerRunHydration & {
  raw: unknown;
  checkpoints: NullBoilerCheckpointHydration[];
};

export type NullBoilerCheckpointHydration = {
  id: string;
  runId: string;
  stepId: string;
  parentId: string | null;
  version: number | null;
  createdAtMs: number | null;
  completedNodes: string[];
  metadata: unknown;
  raw: unknown;
};

export type NullBoilerRunHydration = {
  runId: string;
  status: string;
  createdAtMs: number | null;
  updatedAtMs: number | null;
  checkpointCount: number | null;
};

export type WorkflowHydration = {
  failedRun: NullBoilerRunHydration | null;
  recoveredRun: NullBoilerRunHydration | null;
  checkpoint: NullBoilerCheckpointHydration | null;
  loadedAtMs: number;
  scannedRunCount: number;
};

export function missionWorkflowHydrationKey(snapshot: MissionControlState): string {
  const refs = missionWorkflowRefs(snapshot);
  return [
    refs.scenarioId,
    refs.missionId,
    refs.failedRunId,
    refs.recoveredRunId,
    refs.checkpointId,
  ].join(':');
}

export function missionWorkflowHasRefs(snapshot: MissionControlState): boolean {
  const refs = missionWorkflowRefs(snapshot);
  return Boolean(refs.failedRunId || refs.recoveredRunId || refs.checkpointId);
}

export async function hydrateMissionWorkflowPanels(
  api: WorkflowHydrationApi,
  snapshot: MissionControlState,
): Promise<WorkflowHydration | null> {
  const refs = missionWorkflowRefs(snapshot);
  if (!missionWorkflowRefsPresent(refs)) return null;

  try {
    const page = await api.listRunsPage({ limit: 50 });
    const summaries = Array.isArray(page?.items) ? page.items : [];
    if (summaries.length === 0) return null;

    const candidates = (
      await Promise.all(summaries.map((summary) => loadRunCandidate(api, summary)))
    ).filter((candidate): candidate is RunCandidate => Boolean(candidate));

    const checkpoint = selectMissionCheckpoint(candidates, refs);
    const checkpointId = checkpoint?.id || refs.checkpointId;
    const failedRun = selectFailedRun(candidates, refs, checkpoint);
    const recoveredRun = selectRecoveredRun(candidates, refs, checkpointId);

    if (!failedRun && !recoveredRun && !checkpoint) return null;
    return {
      failedRun: failedRun ? publicRun(failedRun) : null,
      recoveredRun: recoveredRun ? publicRun(recoveredRun) : null,
      checkpoint,
      loadedAtMs: Date.now(),
      scannedRunCount: candidates.length,
    };
  } catch {
    return null;
  }
}

function missionWorkflowRefs(snapshot: MissionControlState): MissionWorkflowRefs {
  return {
    scenarioId: snapshot.scenario_id || '',
    missionId: snapshot.mission_id || snapshot.scenario_id || '',
    failedRunId: snapshot.failure?.run_id || snapshot.failed_run_id || '',
    recoveredRunId: snapshot.recovery?.run_id || snapshot.recovered_run_id || '',
    checkpointId: snapshot.failure?.checkpoint_id || '',
  };
}

function missionWorkflowRefsPresent(refs: MissionWorkflowRefs): boolean {
  return Boolean(refs.failedRunId || refs.recoveredRunId || refs.checkpointId);
}

async function loadRunCandidate(api: WorkflowHydrationApi, summary: unknown): Promise<RunCandidate | null> {
  const summaryId = readString(summary, 'id') || readString(summary, 'run_id');
  if (!summaryId) return null;

  try {
    const detail = await api.getRun(summaryId);
    const rawRun = mergeRun(summary, detail);
    const runId = readString(rawRun, 'id') || readString(rawRun, 'run_id') || summaryId;
    const checkpoints = await loadCheckpoints(api, runId);
    const checkpointCount = readNumber(rawRun, 'checkpoint_count') ?? checkpoints.length;
    return {
      runId,
      status: readString(rawRun, 'status') || 'unknown',
      createdAtMs: readTimestamp(rawRun, 'created_at_ms', 'created_at'),
      updatedAtMs: readTimestamp(rawRun, 'updated_at_ms', 'updated_at'),
      checkpointCount,
      raw: rawRun,
      checkpoints,
    };
  } catch {
    return null;
  }
}

async function loadCheckpoints(
  api: WorkflowHydrationApi,
  runId: string,
): Promise<NullBoilerCheckpointHydration[]> {
  try {
    const checkpoints = await api.listCheckpoints(runId);
    return (Array.isArray(checkpoints) ? checkpoints : [])
      .map((checkpoint) => normalizeCheckpoint(checkpoint))
      .filter((checkpoint): checkpoint is NullBoilerCheckpointHydration => Boolean(checkpoint));
  } catch {
    return [];
  }
}

function normalizeCheckpoint(raw: unknown): NullBoilerCheckpointHydration | null {
  const id = readString(raw, 'id') || readString(raw, 'checkpoint_id');
  const runId = readString(raw, 'run_id');
  if (!id || !runId) return null;
  return {
    id,
    runId,
    stepId: readString(raw, 'step_id') || readString(raw, 'step_name') || readString(raw, 'after_step') || '',
    parentId: readString(raw, 'parent_id') || null,
    version: readNumber(raw, 'version'),
    createdAtMs: readTimestamp(raw, 'created_at_ms', 'created_at'),
    completedNodes: readStringArray(raw, 'completed_nodes'),
    metadata: readField(raw, 'metadata') ?? null,
    raw,
  };
}

function selectMissionCheckpoint(
  candidates: RunCandidate[],
  refs: MissionWorkflowRefs,
): NullBoilerCheckpointHydration | null {
  if (refs.checkpointId) {
    for (const candidate of candidates) {
      const exact = candidate.checkpoints.find((checkpoint) => checkpoint.id === refs.checkpointId);
      if (exact) return exact;
    }
  }

  for (const candidate of candidates) {
    const matched = [...candidate.checkpoints]
      .reverse()
      .find((checkpoint) => checkpointCarriesMissionRef(checkpoint, refs));
    if (matched) return matched;
  }

  return null;
}

function selectFailedRun(
  candidates: RunCandidate[],
  refs: MissionWorkflowRefs,
  checkpoint: NullBoilerCheckpointHydration | null,
): RunCandidate | null {
  if (checkpoint) {
    const owner = candidates.find((candidate) => candidate.runId === checkpoint.runId);
    if (owner) return owner;
  }

  if (refs.failedRunId) {
    const exact = candidates.find((candidate) => candidate.runId === refs.failedRunId);
    if (exact) return exact;
  }

  return candidates.find((candidate) => runCarriesMissionRef(candidate, refs, refs.failedRunId)) || null;
}

function selectRecoveredRun(
  candidates: RunCandidate[],
  refs: MissionWorkflowRefs,
  checkpointId: string,
): RunCandidate | null {
  if (refs.recoveredRunId) {
    const exact = candidates.find((candidate) => candidate.runId === refs.recoveredRunId);
    if (exact) return exact;
  }

  if (checkpointId) {
    const forked = candidates.find((candidate) =>
      candidate.checkpoints.some((checkpoint) => checkpoint.parentId === checkpointId),
    );
    if (forked) return forked;
  }

  return candidates.find((candidate) => runCarriesMissionRef(candidate, refs, refs.recoveredRunId)) || null;
}

function checkpointCarriesMissionRef(
  checkpoint: NullBoilerCheckpointHydration,
  refs: MissionWorkflowRefs,
): boolean {
  if (refs.checkpointId && checkpoint.id === refs.checkpointId) return true;
  return valueCarriesMissionRef(checkpoint.raw, refs);
}

function runCarriesMissionRef(candidate: RunCandidate, refs: MissionWorkflowRefs, runId: string): boolean {
  if (runId && candidate.runId === runId) return true;
  if (runId && valueCarriesString(candidate.raw, runId)) return true;
  return valueCarriesMissionRef(candidate.raw, refs);
}

function valueCarriesMissionRef(value: unknown, refs: MissionWorkflowRefs): boolean {
  if (refs.scenarioId && valueCarriesNamedString(value, refs.scenarioId, [
    'scenario_id',
    'mission_control_scenario_id',
    'nullhub_mission_scenario_id',
  ])) return true;

  if (refs.missionId && valueCarriesNamedString(value, refs.missionId, [
    'mission_id',
    'nullhub_mission_id',
    'mission_control_id',
  ])) return true;

  if (refs.checkpointId && valueCarriesNamedString(value, refs.checkpointId, [
    'checkpoint_id',
    'forked_from_checkpoint',
    'forked_from_checkpoint_id',
    'parent_checkpoint_id',
  ])) return true;

  return false;
}

function valueCarriesNamedString(value: unknown, expected: string, fieldNames: string[], depth = 0): boolean {
  if (!expected || depth > 5 || value == null || typeof value !== 'object') return false;
  if (Array.isArray(value)) {
    return value.some((item) => valueCarriesNamedString(item, expected, fieldNames, depth + 1));
  }
  for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
    if (fieldNames.includes(key) && item === expected) return true;
    if (valueCarriesNamedString(item, expected, fieldNames, depth + 1)) return true;
  }
  return false;
}

function valueCarriesString(value: unknown, expected: string, depth = 0): boolean {
  if (!expected || depth > 5 || value == null) return false;
  if (typeof value === 'string') return value === expected;
  if (typeof value !== 'object') return false;
  if (Array.isArray(value)) return value.some((item) => valueCarriesString(item, expected, depth + 1));
  return Object.values(value as Record<string, unknown>).some((item) =>
    valueCarriesString(item, expected, depth + 1),
  );
}

function publicRun(candidate: RunCandidate): NullBoilerRunHydration {
  return {
    runId: candidate.runId,
    status: candidate.status,
    createdAtMs: candidate.createdAtMs,
    updatedAtMs: candidate.updatedAtMs,
    checkpointCount: candidate.checkpointCount,
  };
}

function mergeRun(summary: unknown, detail: unknown): unknown {
  if (isRecord(summary) && isRecord(detail)) return { ...summary, ...detail };
  return detail || summary;
}

function readField(value: unknown, key: string): unknown {
  return isRecord(value) ? value[key] : undefined;
}

function readString(value: unknown, key: string): string {
  const field = readField(value, key);
  return typeof field === 'string' ? field : '';
}

function readNumber(value: unknown, key: string): number | null {
  const field = readField(value, key);
  return typeof field === 'number' && Number.isFinite(field) ? field : null;
}

function readTimestamp(value: unknown, msKey: string, isoKey: string): number | null {
  const ms = readNumber(value, msKey);
  if (ms != null) return ms;
  const iso = readString(value, isoKey);
  if (!iso) return null;
  const parsed = Date.parse(iso);
  return Number.isFinite(parsed) ? parsed : null;
}

function readStringArray(value: unknown, key: string): string[] {
  const field = readField(value, key);
  if (!Array.isArray(field)) return [];
  return field.filter((item): item is string => typeof item === 'string');
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value && typeof value === 'object' && !Array.isArray(value));
}
