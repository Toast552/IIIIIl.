type RequestFn = <T>(path: string, options?: RequestInit) => Promise<T>;

export type MissionControlStatus = 'idle' | 'running' | 'intervention_required' | 'completed';
export type MissionControlPhase =
  | 'idle'
  | 'launching'
  | 'research'
  | 'coding'
  | 'checkpoint'
  | 'testing'
  | 'failed'
  | 'forking'
  | 'patching'
  | 'retesting'
  | 'review'
  | 'completed';
export type MissionControlControls = {
  can_launch: boolean;
  can_recover: boolean;
  can_reset: boolean;
};
export type MissionControlAgent = {
  id: string;
  role: string;
  status: string;
  current_step: string;
};
export type MissionControlGraphNode = {
  id: string;
  label: string;
  kind: string;
  status: string;
};
export type MissionControlGraphEdge = {
  from: string;
  to: string;
  status: string;
};
export type MissionControlTraceRef = {
  kind: 'span' | 'eval';
  run_id: string | null;
  trace_id: string | null;
  span_id: string | null;
  eval_key: string | null;
  operation: string;
};
export type MissionControlEvent = {
  at_ms: number;
  source: string;
  level: string;
  title: string;
  detail: string;
  status: string;
  trace: MissionControlTraceRef | null;
};
export type MissionControlTelemetry = {
  runs: number;
  spans: number;
  evals: number;
  errors: number;
  total_tokens: number;
  total_cost_usd: number;
  verdict: string;
};
export type MissionControlWorkflowEvidenceStatus =
  | 'available'
  | 'not_configured'
  | 'unavailable'
  | 'not_found'
  | 'ambiguous'
  | 'schema_mismatch';
export type MissionControlWorkflowEvidenceRun = {
  run_id: string;
  status: string;
  created_at_ms: number | null;
  updated_at_ms: number | null;
  checkpoint_count: number | null;
};
export type MissionControlWorkflowEvidenceCheckpoint = {
  id: string;
  run_id: string;
  step_id: string;
  parent_id: string | null;
  version: number | null;
  created_at_ms: number | null;
  completed_nodes: string[];
  metadata: unknown;
};
export type MissionControlWorkflowEvidence = {
  status: MissionControlWorkflowEvidenceStatus | string;
  source: string;
  boiler_instance: string | null;
  failed_run: MissionControlWorkflowEvidenceRun | null;
  recovered_run: MissionControlWorkflowEvidenceRun | null;
  checkpoint: MissionControlWorkflowEvidenceCheckpoint | null;
  scanned_run_count: number;
  reason: string | null;
};
export type MissionControlFailure = {
  run_id: string;
  checkpoint_id: string;
  failed_step: string;
  error_message: string;
  suggested_intervention: string;
};
export type MissionControlRecovery = {
  run_id: string;
  forked_from: string;
  human_instruction: string;
  status: string;
};
export type MissionControlReplayArtifactPanel = {
  artifact_kind: string;
  artifact_role: 'failed' | 'recovered' | string;
  run_id: string;
  workflow_run_id: string | null;
  workflow_status: string | null;
  phase: string;
  status: string;
  headline: string;
  verdict: string;
  trace_id: string | null;
  checkpoint_id: string | null;
  checkpoint_step: string | null;
  forked_from: string | null;
  human_instruction: string | null;
  failure_message: string | null;
  telemetry: MissionControlTelemetry;
};
export type MissionControlReplayArtifactDelta = {
  verdict_changed: boolean;
  checkpoint_reused: boolean;
  spans_delta: number;
  evals_delta: number;
  errors_delta: number;
  tokens_delta: number;
  cost_delta_usd: number;
};
export type MissionControlReplayComparison = {
  failed: MissionControlReplayArtifactPanel;
  recovered: MissionControlReplayArtifactPanel;
  delta: MissionControlReplayArtifactDelta;
};
export type MissionControlState = {
  schema_version: number;
  mode: string;
  scenario_id: string;
  scenario_version: string;
  generated_at_ms: number;
  mission_id: string;
  title: string;
  status: MissionControlStatus;
  phase: MissionControlPhase;
  headline: string;
  elapsed_ms: number;
  progress: number;
  active_run_id: string | null;
  failed_run_id: string | null;
  recovered_run_id: string | null;
  controls: MissionControlControls;
  agents: MissionControlAgent[];
  graph: {
    nodes: MissionControlGraphNode[];
    edges: MissionControlGraphEdge[];
  };
  events: MissionControlEvent[];
  telemetry: MissionControlTelemetry;
  workflow_evidence: MissionControlWorkflowEvidence;
  replay_comparison: MissionControlReplayComparison | null;
  failure: MissionControlFailure | null;
  recovery: MissionControlRecovery | null;
};
export type MissionControlComponentMapping = {
  component: string;
  role: string;
  evidence: string[];
};
export type MissionControlWorkflowMapping = MissionControlComponentMapping & {
  status: string;
  source: string;
  boiler_instance: string | null;
  checkpoint_id: string;
  failed_run_id: string;
  recovered_run_id: string;
  human_instruction: string;
};
export type MissionControlNullWatchMapping = MissionControlComponentMapping & {
  failed_run_id: string;
  recovered_run_id: string;
  trace_ref_source: string;
};
export type MissionControlReplayArtifact = {
  artifact_schema_version: number;
  artifact_kind: string;
  generated_at_ms: number;
  replay_fixture_path: string;
  scenario_id: string;
  scenario_version: string;
  mode: string;
  snapshot: MissionControlState;
  replay_fixture: unknown;
  workflow_evidence: MissionControlWorkflowEvidence;
  ecosystem_mapping: {
    nulltickets: MissionControlComponentMapping;
    nullboiler: MissionControlWorkflowMapping;
    nullclaw: MissionControlComponentMapping;
    nullwatch: MissionControlNullWatchMapping;
  };
};
export type MissionControlReplayRecord = {
  id: string;
  saved_at_ms: number;
  generated_at_ms: number;
  scenario_id: string;
  scenario_version: string;
  mission_id: string;
  title: string;
  status: string;
  phase: string;
  artifact_kind: string;
  artifact_path: string;
  size_bytes: number;
};
export type MissionControlReplayList = {
  items: MissionControlReplayRecord[];
  count: number;
};
export type MissionControlReplaySaveResult = {
  record: MissionControlReplayRecord;
  artifact: MissionControlReplayArtifact;
};

export function createMissionControlApi(request: RequestFn) {
  return {
    getMissionControlState: () => request<MissionControlState>('/mission-control/state'),
    getMissionControlReplay: () => request<MissionControlReplayArtifact>('/mission-control/replay'),
    saveMissionControlReplay: () =>
      request<MissionControlReplaySaveResult>('/mission-control/replay/save', { method: 'POST' }),
    listMissionControlReplays: () => request<MissionControlReplayList>('/mission-control/replays'),
    getStoredMissionControlReplay: (id: string) =>
      request<MissionControlReplayArtifact>(`/mission-control/replays/${encodeURIComponent(id)}`),
    launchMissionControl: () =>
      request<MissionControlState>('/mission-control/launch', { method: 'POST' }),
    resetMissionControl: () =>
      request<MissionControlState>('/mission-control/reset', { method: 'POST' }),
    recoverMissionControl: () =>
      request<MissionControlState>('/mission-control/recover', { method: 'POST' }),
  };
}
