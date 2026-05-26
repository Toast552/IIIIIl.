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
export type MissionControlObservabilityMapping = MissionControlComponentMapping & {
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
    nullwatch: MissionControlObservabilityMapping;
  };
};

export function createMissionControlApi(request: RequestFn) {
  return {
    getMissionControlState: () => request<MissionControlState>('/mission-control/state'),
    getMissionControlReplay: () => request<MissionControlReplayArtifact>('/mission-control/replay'),
    launchMissionControl: () =>
      request<MissionControlState>('/mission-control/launch', { method: 'POST' }),
    resetMissionControl: () =>
      request<MissionControlState>('/mission-control/reset', { method: 'POST' }),
    recoverMissionControl: () =>
      request<MissionControlState>('/mission-control/recover', { method: 'POST' }),
  };
}
