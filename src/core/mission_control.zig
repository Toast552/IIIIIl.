const std = @import("std");
const replay = @import("mission_control_replay.zig");

pub const RuntimeState = struct {
    launched: bool = false,
    started_at_ms: i64 = 0,
    recovered: bool = false,
    recovery_started_at_ms: i64 = 0,
};

pub const MissionControls = struct {
    can_launch: bool,
    can_recover: bool,
    can_reset: bool,
};

pub const Agent = struct {
    id: []const u8,
    role: []const u8,
    status: []const u8,
    current_step: []const u8,
};

pub const GraphNode = struct {
    id: []const u8,
    label: []const u8,
    kind: []const u8,
    status: []const u8,
};

pub const GraphEdge = struct {
    from: []const u8,
    to: []const u8,
    status: []const u8,
};

pub const MissionGraph = struct {
    nodes: []const GraphNode,
    edges: []const GraphEdge,
};

pub const MissionEvent = struct {
    at_ms: i64,
    source: []const u8,
    level: []const u8,
    title: []const u8,
    detail: []const u8,
    status: []const u8,
    trace: ?replay.EventTraceDef,
};

pub const MissionTelemetry = struct {
    runs: usize,
    spans: usize,
    evals: usize,
    errors: usize,
    total_tokens: usize,
    total_cost_usd: f64,
    verdict: []const u8,
};

pub const WorkflowEvidenceRefs = struct {
    scenario_id: []const u8,
    mission_id: []const u8,
    failed_run_id: []const u8,
    recovered_run_id: []const u8,
    checkpoint_id: []const u8,
};

pub const WorkflowEvidenceRun = struct {
    run_id: []const u8,
    status: []const u8,
    created_at_ms: ?i64 = null,
    updated_at_ms: ?i64 = null,
    checkpoint_count: ?usize = null,
};

pub const WorkflowEvidenceCheckpoint = struct {
    id: []const u8,
    run_id: []const u8,
    step_id: []const u8,
    parent_id: ?[]const u8 = null,
    version: ?i64 = null,
    created_at_ms: ?i64 = null,
    completed_nodes: []const []const u8 = &.{},
    metadata: ?std.json.Value = null,
};

pub const WorkflowEvidence = struct {
    status: []const u8,
    source: []const u8 = "nullboiler",
    boiler_instance: ?[]const u8 = null,
    failed_run: ?WorkflowEvidenceRun = null,
    recovered_run: ?WorkflowEvidenceRun = null,
    checkpoint: ?WorkflowEvidenceCheckpoint = null,
    scanned_run_count: usize = 0,
    reason: ?[]const u8 = null,
};

pub const FailurePanel = struct {
    run_id: []const u8,
    checkpoint_id: []const u8,
    failed_step: []const u8,
    error_message: []const u8,
    suggested_intervention: []const u8,
};

pub const RecoveryPanel = struct {
    run_id: []const u8,
    forked_from: []const u8,
    human_instruction: []const u8,
    status: []const u8,
};

pub const ReplayArtifactPanel = struct {
    artifact_kind: []const u8,
    artifact_role: []const u8,
    run_id: []const u8,
    workflow_run_id: ?[]const u8,
    workflow_status: ?[]const u8,
    phase: []const u8,
    status: []const u8,
    headline: []const u8,
    verdict: []const u8,
    trace_id: ?[]const u8,
    checkpoint_id: ?[]const u8,
    checkpoint_step: ?[]const u8,
    forked_from: ?[]const u8,
    human_instruction: ?[]const u8,
    failure_message: ?[]const u8,
    telemetry: MissionTelemetry,
};

pub const ReplayArtifactDelta = struct {
    verdict_changed: bool,
    checkpoint_reused: bool,
    spans_delta: i64,
    evals_delta: i64,
    errors_delta: i64,
    tokens_delta: i64,
    cost_delta_usd: f64,
};

pub const ReplayArtifactComparison = struct {
    failed: ReplayArtifactPanel,
    recovered: ReplayArtifactPanel,
    delta: ReplayArtifactDelta,
};

pub const MissionSnapshot = struct {
    schema_version: u8,
    mode: []const u8,
    scenario_id: []const u8,
    scenario_version: []const u8,
    generated_at_ms: i64,
    mission_id: []const u8,
    title: []const u8,
    status: []const u8,
    phase: []const u8,
    headline: []const u8,
    elapsed_ms: i64,
    progress: u8,
    active_run_id: ?[]const u8,
    failed_run_id: ?[]const u8,
    recovered_run_id: ?[]const u8,
    controls: MissionControls,
    agents: []const Agent,
    graph: MissionGraph,
    events: []const MissionEvent,
    telemetry: MissionTelemetry,
    workflow_evidence: WorkflowEvidence,
    replay_comparison: ?ReplayArtifactComparison,
    failure: ?FailurePanel,
    recovery: ?RecoveryPanel,
};

pub const ComponentMapping = struct {
    component: []const u8,
    role: []const u8,
    evidence: []const []const u8,
};

pub const WorkflowMapping = struct {
    component: []const u8,
    role: []const u8,
    status: []const u8,
    source: []const u8,
    boiler_instance: ?[]const u8,
    checkpoint_id: []const u8,
    failed_run_id: []const u8,
    recovered_run_id: []const u8,
    human_instruction: []const u8,
    evidence: []const []const u8,
};

pub const ObservabilityMapping = struct {
    component: []const u8,
    role: []const u8,
    failed_run_id: []const u8,
    recovered_run_id: []const u8,
    trace_ref_source: []const u8,
    evidence: []const []const u8,
};

pub const ReplayArtifactMapping = struct {
    nulltickets: ComponentMapping,
    nullboiler: WorkflowMapping,
    nullclaw: ComponentMapping,
    nullwatch: ObservabilityMapping,
};

pub const ReplayArtifact = struct {
    artifact_schema_version: u8,
    artifact_kind: []const u8,
    generated_at_ms: i64,
    replay_fixture_path: []const u8,
    scenario_id: []const u8,
    scenario_version: []const u8,
    mode: []const u8,
    snapshot: MissionSnapshot,
    replay_fixture: replay.ReplayFixture,
    workflow_evidence: WorkflowEvidence,
    ecosystem_mapping: ReplayArtifactMapping,
};

pub const SnapshotView = struct {
    parsed: std.json.Parsed(replay.ReplayFixture),
    agents: []Agent,
    nodes: []GraphNode,
    edges: []GraphEdge,
    events: []MissionEvent,
    snapshot: MissionSnapshot,

    pub fn deinit(self: *SnapshotView, allocator: std.mem.Allocator) void {
        allocator.free(self.events);
        allocator.free(self.edges);
        allocator.free(self.nodes);
        allocator.free(self.agents);
        self.parsed.deinit();
        self.* = undefined;
    }
};

pub const ReplayArtifactView = struct {
    snapshot_view: SnapshotView,
    artifact: ReplayArtifact,

    pub fn deinit(self: *ReplayArtifactView, allocator: std.mem.Allocator) void {
        self.snapshot_view.deinit(allocator);
        self.* = undefined;
    }
};

pub fn reset(runtime: *RuntimeState) void {
    runtime.* = .{};
}

pub fn canLaunch(runtime: RuntimeState) bool {
    return !runtime.launched;
}

pub fn launch(runtime: *RuntimeState, now_ms: i64) bool {
    if (!canLaunch(runtime.*)) return false;
    runtime.* = .{
        .launched = true,
        .started_at_ms = now_ms,
    };
    return true;
}

pub fn parseReplay(allocator: std.mem.Allocator) !std.json.Parsed(replay.ReplayFixture) {
    return replay.parseValidated(allocator);
}

pub fn canRecoverAt(allocator: std.mem.Allocator, runtime: RuntimeState, now_ms: i64) !bool {
    var parsed = try parseReplay(allocator);
    defer parsed.deinit();

    return canRecoverWithFixture(parsed.value, runtime, now_ms);
}

pub fn recover(allocator: std.mem.Allocator, runtime: *RuntimeState, now_ms: i64) !bool {
    var parsed = try parseReplay(allocator);
    defer parsed.deinit();

    return recoverWithFixture(parsed.value, runtime, now_ms);
}

pub fn recoverWithFixture(fixture: replay.ReplayFixture, runtime: *RuntimeState, now_ms: i64) bool {
    if (!canRecoverWithFixture(fixture, runtime.*, now_ms)) return false;
    runtime.recovered = true;
    runtime.recovery_started_at_ms = now_ms;
    return true;
}

pub fn canRecoverWithFixture(fixture: replay.ReplayFixture, runtime: RuntimeState, now_ms: i64) bool {
    const elapsed_ms = elapsedSince(runtime.started_at_ms, now_ms);
    const recovery_elapsed_ms = elapsedSince(runtime.recovery_started_at_ms, now_ms);
    const phase = currentPhase(fixture, runtime, elapsed_ms, recovery_elapsed_ms);
    return canRecoverPhase(fixture, runtime, phase);
}

pub fn workflowEvidenceRefs(fixture: replay.ReplayFixture) WorkflowEvidenceRefs {
    return .{
        .scenario_id = fixture.scenario_id,
        .mission_id = fixture.scenario_id,
        .failed_run_id = fixture.run_ids.failed,
        .recovered_run_id = fixture.run_ids.recovered,
        .checkpoint_id = fixture.checkpoint_id,
    };
}

pub fn workflowEvidenceUnavailable(reason: []const u8) WorkflowEvidence {
    return .{
        .status = "unavailable",
        .reason = reason,
    };
}

/// Returns an allocator-owned copy of workflow evidence for request/serialization lifetimes.
pub fn cloneWorkflowEvidence(allocator: std.mem.Allocator, evidence: WorkflowEvidence) !WorkflowEvidence {
    return .{
        .status = try allocator.dupe(u8, evidence.status),
        .source = try allocator.dupe(u8, evidence.source),
        .boiler_instance = try cloneOptionalString(allocator, evidence.boiler_instance),
        .failed_run = if (evidence.failed_run) |run| try cloneWorkflowEvidenceRun(allocator, run) else null,
        .recovered_run = if (evidence.recovered_run) |run| try cloneWorkflowEvidenceRun(allocator, run) else null,
        .checkpoint = if (evidence.checkpoint) |checkpoint| try cloneWorkflowEvidenceCheckpoint(allocator, checkpoint) else null,
        .scanned_run_count = evidence.scanned_run_count,
        .reason = try cloneOptionalString(allocator, evidence.reason),
    };
}

pub fn cloneJsonValue(allocator: std.mem.Allocator, value: std.json.Value) !std.json.Value {
    const rendered = try std.json.Stringify.valueAlloc(allocator, value, .{});
    defer allocator.free(rendered);
    return try std.json.parseFromSliceLeaky(std.json.Value, allocator, rendered, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
}

fn cloneWorkflowEvidenceRun(allocator: std.mem.Allocator, run: WorkflowEvidenceRun) !WorkflowEvidenceRun {
    return .{
        .run_id = try allocator.dupe(u8, run.run_id),
        .status = try allocator.dupe(u8, run.status),
        .created_at_ms = run.created_at_ms,
        .updated_at_ms = run.updated_at_ms,
        .checkpoint_count = run.checkpoint_count,
    };
}

fn cloneWorkflowEvidenceCheckpoint(allocator: std.mem.Allocator, checkpoint: WorkflowEvidenceCheckpoint) !WorkflowEvidenceCheckpoint {
    return .{
        .id = try allocator.dupe(u8, checkpoint.id),
        .run_id = try allocator.dupe(u8, checkpoint.run_id),
        .step_id = try allocator.dupe(u8, checkpoint.step_id),
        .parent_id = try cloneOptionalString(allocator, checkpoint.parent_id),
        .version = checkpoint.version,
        .created_at_ms = checkpoint.created_at_ms,
        .completed_nodes = try cloneStringSlice(allocator, checkpoint.completed_nodes),
        .metadata = if (checkpoint.metadata) |metadata| try cloneJsonValue(allocator, metadata) else null,
    };
}

fn cloneOptionalString(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
    if (value) |text| return try allocator.dupe(u8, text);
    return null;
}

fn cloneStringSlice(allocator: std.mem.Allocator, values: []const []const u8) ![]const []const u8 {
    if (values.len == 0) return &.{};
    const out = try allocator.alloc([]const u8, values.len);
    for (values, 0..) |value, i| {
        out[i] = try allocator.dupe(u8, value);
    }
    return out;
}

pub fn buildSnapshotViewWithEvidence(allocator: std.mem.Allocator, runtime: RuntimeState, now_ms: i64, workflow_evidence: WorkflowEvidence) !SnapshotView {
    const parsed = try parseReplay(allocator);
    return buildSnapshotViewFromParsed(allocator, parsed, runtime, now_ms, workflow_evidence);
}

pub fn buildSnapshotViewFromParsed(
    allocator: std.mem.Allocator,
    parsed_fixture: std.json.Parsed(replay.ReplayFixture),
    runtime: RuntimeState,
    now_ms: i64,
    workflow_evidence: WorkflowEvidence,
) !SnapshotView {
    var parsed = parsed_fixture;
    errdefer parsed.deinit();
    const fixture = parsed.value;

    const elapsed_ms = elapsedSince(runtime.started_at_ms, now_ms);
    const recovery_elapsed_ms = elapsedSince(runtime.recovery_started_at_ms, now_ms);
    const phase = currentPhase(fixture, runtime, elapsed_ms, recovery_elapsed_ms);
    const agents = try buildAgents(allocator, fixture, phase);
    errdefer allocator.free(agents);
    const nodes = try buildNodes(allocator, fixture, phase);
    errdefer allocator.free(nodes);
    const edges = try buildEdges(allocator, fixture, phase);
    errdefer allocator.free(edges);
    const events = try buildEvents(allocator, fixture, phase);
    errdefer allocator.free(events);
    const snapshot = buildSnapshot(
        fixture,
        runtime,
        now_ms,
        elapsed_ms,
        phase,
        agents,
        nodes,
        edges,
        events,
        workflow_evidence,
    );
    return .{
        .parsed = parsed,
        .agents = agents,
        .nodes = nodes,
        .edges = edges,
        .events = events,
        .snapshot = snapshot,
    };
}

pub fn buildReplayArtifactViewWithEvidence(allocator: std.mem.Allocator, runtime: RuntimeState, now_ms: i64, workflow_evidence: WorkflowEvidence) !ReplayArtifactView {
    const parsed = try parseReplay(allocator);
    return buildReplayArtifactViewFromParsed(allocator, parsed, runtime, now_ms, workflow_evidence);
}

pub fn buildReplayArtifactViewFromParsed(
    allocator: std.mem.Allocator,
    parsed_fixture: std.json.Parsed(replay.ReplayFixture),
    runtime: RuntimeState,
    now_ms: i64,
    workflow_evidence: WorkflowEvidence,
) !ReplayArtifactView {
    var snapshot_view = try buildSnapshotViewFromParsed(allocator, parsed_fixture, runtime, now_ms, workflow_evidence);
    errdefer snapshot_view.deinit(allocator);
    const fixture = snapshot_view.parsed.value;
    const artifact = ReplayArtifact{
        .artifact_schema_version = 1,
        .artifact_kind = "nullhub.mission_control.replay",
        .generated_at_ms = now_ms,
        .replay_fixture_path = "src/core/mission_control/code_red.v1.json",
        .scenario_id = fixture.scenario_id,
        .scenario_version = fixture.scenario_version,
        .mode = fixture.mode,
        .snapshot = snapshot_view.snapshot,
        .replay_fixture = fixture,
        .workflow_evidence = workflow_evidence,
        .ecosystem_mapping = replayArtifactMapping(fixture, workflow_evidence),
    };
    return .{
        .snapshot_view = snapshot_view,
        .artifact = artifact,
    };
}

fn replayArtifactMapping(fixture: replay.ReplayFixture, workflow_evidence: WorkflowEvidence) ReplayArtifactMapping {
    const workflow_checkpoint_id = if (workflow_evidence.checkpoint) |checkpoint| checkpoint.id else fixture.checkpoint_id;
    const workflow_failed_run_id = if (workflow_evidence.failed_run) |run| run.run_id else fixture.run_ids.failed;
    const workflow_recovered_run_id = if (workflow_evidence.recovered_run) |run| run.run_id else fixture.run_ids.recovered;

    return .{
        .nulltickets = .{
            .component = "nulltickets",
            .role = "Tracker-style task source and terminal workflow status.",
            .evidence = &.{ "events[source=nulltickets]", "graph.nodes[kind=tracker]" },
        },
        .nullboiler = .{
            .component = "nullboiler",
            .role = "Workflow execution, checkpointing, dispatch, and fork recovery.",
            .status = workflow_evidence.status,
            .source = workflow_evidence.source,
            .boiler_instance = workflow_evidence.boiler_instance,
            .checkpoint_id = workflow_checkpoint_id,
            .failed_run_id = workflow_failed_run_id,
            .recovered_run_id = workflow_recovered_run_id,
            .human_instruction = fixture.human_instruction,
            .evidence = &.{ "workflow_evidence", "phases", "graph.edges", "events[source=nullboiler]", "failure.checkpoint_id", "recovery.forked_from" },
        },
        .nullclaw = .{
            .component = "nullclaw",
            .role = "Lightweight role agents that perform research, coding, testing, and review steps.",
            .evidence = &.{ "agents", "events[source=nullclaw]", "graph.nodes[kind=agent]" },
        },
        .nullwatch = .{
            .component = "nullwatch",
            .role = "Run, span, eval, token, cost, and failure telemetry references.",
            .failed_run_id = fixture.run_ids.failed,
            .recovered_run_id = fixture.run_ids.recovered,
            .trace_ref_source = "events[].trace",
            .evidence = &.{ "events[].trace", "telemetry", "failure.run_id", "recovery.run_id" },
        },
    };
}

fn buildSnapshot(
    fixture: replay.ReplayFixture,
    runtime: RuntimeState,
    now_ms: i64,
    elapsed_ms: i64,
    phase: []const u8,
    agents: []const Agent,
    nodes: []const GraphNode,
    edges: []const GraphEdge,
    events: []const MissionEvent,
    workflow_evidence: WorkflowEvidence,
) MissionSnapshot {
    const failed_visible = isAtOrAfter(fixture, phase, fixture.failure.visible_from_phase);
    const recovered_visible = runtime.recovered;
    const recovered_artifact_visible = recovered_visible and std.mem.eql(u8, phase, "completed");
    const phase_def = replay.phaseById(fixture, phase).?;

    return .{
        .schema_version = fixture.schema_version,
        .mode = fixture.mode,
        .scenario_id = fixture.scenario_id,
        .scenario_version = fixture.scenario_version,
        .generated_at_ms = now_ms,
        .mission_id = fixture.scenario_id,
        .title = fixture.title,
        .status = phase_def.status,
        .phase = phase,
        .headline = phase_def.headline,
        .elapsed_ms = if (runtime.launched) elapsed_ms else 0,
        .progress = phase_def.progress,
        .active_run_id = activeRunId(fixture, phase),
        .failed_run_id = if (failed_visible) fixture.failure.run_id else null,
        .recovered_run_id = if (recovered_visible) fixture.recovery.run_id else null,
        .controls = .{
            .can_launch = canLaunch(runtime),
            .can_recover = canRecover(fixture, runtime, phase),
            .can_reset = true,
        },
        .agents = agents,
        .graph = .{
            .nodes = nodes,
            .edges = edges,
        },
        .events = events,
        .telemetry = telemetryForPhase(fixture, phase),
        .workflow_evidence = workflow_evidence,
        .replay_comparison = if (failed_visible and recovered_artifact_visible) buildReplayArtifactComparison(fixture, workflow_evidence) else null,
        .failure = if (failed_visible) FailurePanel{
            .run_id = fixture.failure.run_id,
            .checkpoint_id = fixture.failure.checkpoint_id,
            .failed_step = fixture.failure.failed_step,
            .error_message = fixture.failure.error_message,
            .suggested_intervention = fixture.failure.suggested_intervention,
        } else null,
        .recovery = if (recovered_visible) RecoveryPanel{
            .run_id = fixture.recovery.run_id,
            .forked_from = fixture.recovery.forked_from,
            .human_instruction = fixture.recovery.human_instruction,
            .status = if (std.mem.eql(u8, phase, "completed")) "passed" else "replaying",
        } else null,
    };
}

fn buildReplayArtifactComparison(fixture: replay.ReplayFixture, workflow_evidence: WorkflowEvidence) ReplayArtifactComparison {
    const failed = replayArtifactPanel(fixture, workflow_evidence, "failed");
    const recovered = replayArtifactPanel(fixture, workflow_evidence, "recovered");
    return .{
        .failed = failed,
        .recovered = recovered,
        .delta = .{
            .verdict_changed = !std.mem.eql(u8, failed.verdict, recovered.verdict),
            .checkpoint_reused = std.mem.eql(u8, fixture.failure.checkpoint_id, fixture.recovery.forked_from),
            .spans_delta = signedDelta(recovered.telemetry.spans, failed.telemetry.spans),
            .evals_delta = signedDelta(recovered.telemetry.evals, failed.telemetry.evals),
            .errors_delta = signedDelta(recovered.telemetry.errors, failed.telemetry.errors),
            .tokens_delta = signedDelta(recovered.telemetry.total_tokens, failed.telemetry.total_tokens),
            .cost_delta_usd = recovered.telemetry.total_cost_usd - failed.telemetry.total_cost_usd,
        },
    };
}

fn replayArtifactPanel(fixture: replay.ReplayFixture, workflow_evidence: WorkflowEvidence, role: []const u8) ReplayArtifactPanel {
    const is_failed = std.mem.eql(u8, role, "failed");
    const run_id = if (is_failed) fixture.failure.run_id else fixture.recovery.run_id;
    const phase = if (is_failed) "failed" else "completed";
    const phase_def = replay.phaseById(fixture, phase).?;
    const telemetry = telemetryForPhase(fixture, phase);
    const workflow_run = if (is_failed) workflow_evidence.failed_run else workflow_evidence.recovered_run;
    const checkpoint = workflow_evidence.checkpoint;

    return .{
        .artifact_kind = "nullhub.mission_control.run_replay",
        .artifact_role = role,
        .run_id = run_id,
        .workflow_run_id = if (workflow_run) |run| run.run_id else null,
        .workflow_status = if (workflow_run) |run| run.status else null,
        .phase = phase,
        .status = phase_def.status,
        .headline = phase_def.headline,
        .verdict = telemetry.verdict,
        .trace_id = traceIdForRun(fixture, run_id),
        .checkpoint_id = if (is_failed) (if (checkpoint) |value| value.id else fixture.failure.checkpoint_id) else null,
        .checkpoint_step = if (is_failed) (if (checkpoint) |value| value.step_id else fixture.failure.failed_step) else null,
        .forked_from = if (is_failed) null else fixture.recovery.forked_from,
        .human_instruction = if (is_failed) null else fixture.recovery.human_instruction,
        .failure_message = if (is_failed) fixture.failure.error_message else null,
        .telemetry = telemetry,
    };
}

fn traceIdForRun(fixture: replay.ReplayFixture, run_id: []const u8) ?[]const u8 {
    var found: ?[]const u8 = null;
    for (fixture.events) |event| {
        const trace = event.trace orelse continue;
        const trace_run_id = trace.run_id orelse continue;
        if (!std.mem.eql(u8, trace_run_id, run_id)) continue;
        if (trace.trace_id) |trace_id| found = trace_id;
    }
    return found;
}

fn signedDelta(after: usize, before: usize) i64 {
    return @as(i64, @intCast(after)) - @as(i64, @intCast(before));
}

fn elapsedSince(start_ms: i64, now_ms: i64) i64 {
    if (start_ms <= 0 or now_ms <= start_ms) return 0;
    return now_ms - start_ms;
}

fn currentPhase(fixture: replay.ReplayFixture, runtime: RuntimeState, elapsed_ms: i64, recovery_elapsed_ms: i64) []const u8 {
    if (!runtime.launched) return "idle";
    return phaseForTrack(fixture, if (runtime.recovered) "recovery" else "primary", if (runtime.recovered) recovery_elapsed_ms else elapsed_ms);
}

fn phaseForTrack(fixture: replay.ReplayFixture, track: []const u8, elapsed_ms: i64) []const u8 {
    var selected: ?replay.PhaseDef = null;
    for (fixture.phases) |phase| {
        if (!std.mem.eql(u8, phase.track, track)) continue;
        if (phase.starts_at_ms > elapsed_ms) continue;
        if (selected == null or phase.starts_at_ms >= selected.?.starts_at_ms) {
            selected = phase;
        }
    }
    return if (selected) |phase| phase.id else "idle";
}

fn canRecover(fixture: replay.ReplayFixture, runtime: RuntimeState, phase: []const u8) bool {
    return canRecoverPhase(fixture, runtime, phase);
}

fn canRecoverPhase(fixture: replay.ReplayFixture, runtime: RuntimeState, phase: []const u8) bool {
    return runtime.launched and !runtime.recovered and isAtOrAfter(fixture, phase, fixture.failure.visible_from_phase);
}

fn activeRunId(fixture: replay.ReplayFixture, phase: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, phase, "idle")) return null;
    if (isAtOrAfter(fixture, phase, fixture.recovery.visible_from_phase)) return fixture.recovery.run_id;
    return fixture.failure.run_id;
}

fn statusAfter(fixture: replay.ReplayFixture, phase: []const u8, own_phase: []const u8) []const u8 {
    const current_rank = phaseRank(fixture, phase);
    const own_rank = phaseRank(fixture, own_phase);
    if (current_rank > own_rank) return "done";
    if (current_rank == own_rank) return "active";
    return "pending";
}

fn buildAgents(allocator: std.mem.Allocator, fixture: replay.ReplayFixture, phase: []const u8) ![]Agent {
    const agents = try allocator.alloc(Agent, fixture.agents.len);
    for (fixture.agents, 0..) |agent, index| {
        agents[index] = .{
            .id = agent.id,
            .role = agent.role,
            .status = agentStatus(fixture, agent, phase),
            .current_step = agentStep(agent, phase),
        };
    }
    return agents;
}

fn agentStatus(fixture: replay.ReplayFixture, agent: replay.AgentDef, phase: []const u8) []const u8 {
    for (agent.active_phases) |active_phase| {
        if (std.mem.eql(u8, phase, active_phase)) return "active";
    }
    if (agent.failed_phase) |failed_phase| {
        if (std.mem.eql(u8, phase, failed_phase)) return "failed";
    }
    if (agent.blocked_phase) |blocked_phase| {
        if (std.mem.eql(u8, phase, blocked_phase)) return "blocked";
    }
    if (phaseRank(fixture, phase) > phaseRank(fixture, agent.done_after_phase)) return "done";
    return "standby";
}

fn agentStep(agent: replay.AgentDef, phase: []const u8) []const u8 {
    for (agent.steps) |step| {
        if (std.mem.eql(u8, step.phase, phase)) return step.step;
    }
    return "waiting";
}

fn buildNodes(allocator: std.mem.Allocator, fixture: replay.ReplayFixture, phase: []const u8) ![]GraphNode {
    const nodes = try allocator.alloc(GraphNode, fixture.graph.nodes.len);
    for (fixture.graph.nodes, 0..) |node, index| {
        nodes[index] = .{
            .id = node.id,
            .label = node.label,
            .kind = node.kind,
            .status = nodeStatus(fixture, node, phase),
        };
    }
    return nodes;
}

fn nodeStatus(fixture: replay.ReplayFixture, node: replay.GraphNodeDef, phase: []const u8) []const u8 {
    if (node.error_phase) |error_phase| {
        if (std.mem.eql(u8, phase, error_phase)) return "error";
    }
    return statusAfter(fixture, phase, node.phase);
}

fn buildEdges(allocator: std.mem.Allocator, fixture: replay.ReplayFixture, phase: []const u8) ![]GraphEdge {
    const edges = try allocator.alloc(GraphEdge, fixture.graph.edges.len);
    for (fixture.graph.edges, 0..) |edge, index| {
        edges[index] = .{
            .from = edge.from,
            .to = edge.to,
            .status = edgeStatus(fixture, edge, phase),
        };
    }
    return edges;
}

fn edgeStatus(fixture: replay.ReplayFixture, edge: replay.GraphEdgeDef, phase: []const u8) []const u8 {
    if (edge.error_phase) |error_phase| {
        if (std.mem.eql(u8, phase, error_phase)) return "error";
    }
    return statusAfter(fixture, phase, edge.phase);
}

fn buildEvents(allocator: std.mem.Allocator, fixture: replay.ReplayFixture, phase: []const u8) ![]MissionEvent {
    const events = try allocator.alloc(MissionEvent, fixture.events.len);
    for (fixture.events, 0..) |event, index| {
        events[index] = .{
            .at_ms = event.at_ms,
            .source = event.source,
            .level = event.level,
            .title = event.title,
            .detail = event.detail,
            .status = statusAfter(fixture, phase, event.phase),
            .trace = event.trace,
        };
    }
    return events;
}

fn telemetryForPhase(fixture: replay.ReplayFixture, phase: []const u8) MissionTelemetry {
    const current_rank = phaseRank(fixture, phase);
    var selected = fixture.telemetry[0];
    var selected_rank = phaseRank(fixture, selected.phase);
    for (fixture.telemetry) |entry| {
        const entry_rank = phaseRank(fixture, entry.phase);
        if (entry_rank <= current_rank and entry_rank >= selected_rank) {
            selected = entry;
            selected_rank = entry_rank;
        }
    }
    return .{
        .runs = selected.runs,
        .spans = selected.spans,
        .evals = selected.evals,
        .errors = selected.errors,
        .total_tokens = selected.total_tokens,
        .total_cost_usd = selected.total_cost_usd,
        .verdict = selected.verdict,
    };
}

fn phaseRank(fixture: replay.ReplayFixture, phase: []const u8) u8 {
    return replay.phaseRank(fixture, phase) orelse 0;
}

fn isAtOrAfter(fixture: replay.ReplayFixture, phase: []const u8, threshold: []const u8) bool {
    return phaseRank(fixture, phase) >= phaseRank(fixture, threshold);
}

fn snapshotJsonForTest(allocator: std.mem.Allocator, runtime: RuntimeState, now_ms: i64) ![]u8 {
    var view = try buildSnapshotViewWithEvidence(allocator, runtime, now_ms, workflowEvidenceForTest());
    defer view.deinit(allocator);

    return std.json.Stringify.valueAlloc(allocator, view.snapshot, .{ .whitespace = .indent_2 });
}

fn replayArtifactJsonForTest(allocator: std.mem.Allocator, runtime: RuntimeState, now_ms: i64) ![]u8 {
    var view = try buildReplayArtifactViewWithEvidence(allocator, runtime, now_ms, workflowEvidenceForTest());
    defer view.deinit(allocator);

    return std.json.Stringify.valueAlloc(allocator, view.artifact, .{ .whitespace = .indent_2 });
}

fn workflowEvidenceForTest() WorkflowEvidence {
    return .{
        .status = "available",
        .failed_run = .{
            .run_id = "run-demo-failed-primary",
            .status = "failed",
            .checkpoint_count = 1,
        },
        .recovered_run = .{
            .run_id = "run-demo-recovered-fork",
            .status = "completed",
            .checkpoint_count = 1,
        },
        .checkpoint = .{
            .id = "ckpt-demo-code-red-failed",
            .run_id = "run-demo-failed-primary",
            .step_id = "code.build",
        },
        .scanned_run_count = 2,
    };
}

test "buildSnapshotView returns idle mission before launch" {
    const json = try snapshotJsonForTest(std.testing.allocator, .{}, 1_000);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"schema_version\": 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"mode\": \"deterministic_local_replay\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"scenario_id\": \"mission-code-red\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"status\": \"idle\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"phase\": \"idle\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"workflow_evidence\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"can_launch\": true") != null);
}

test "buildSnapshotView exposes failed mission and recover control" {
    const json = try snapshotJsonForTest(std.testing.allocator, .{
        .launched = true,
        .started_at_ms = 1_000,
    }, 11_000);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"status\": \"intervention_required\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"phase\": \"failed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"can_recover\": true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"replay_comparison\": null") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"artifact_role\": \"failed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"artifact_role\": \"recovered\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"trace_id\": \"trace-demo-code-red-primary\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"eval_key\": \"tool_success\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "zig build test exited with status 1") != null);
}

test "buildSnapshotView exposes recovered completed mission" {
    const json = try snapshotJsonForTest(std.testing.allocator, .{
        .launched = true,
        .started_at_ms = 1_000,
        .recovered = true,
        .recovery_started_at_ms = 11_000,
    }, 19_000);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"status\": \"completed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"phase\": \"completed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"recovered_run_id\": \"run-demo-recovered-fork\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"verdict\": \"pass\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"artifact_role\": \"recovered\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"tokens_delta\": 1520") != null);
}

test "buildSnapshotView keeps recovered comparison hidden until completion" {
    const json = try snapshotJsonForTest(std.testing.allocator, .{
        .launched = true,
        .started_at_ms = 1_000,
        .recovered = true,
        .recovery_started_at_ms = 11_000,
    }, 12_000);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"status\": \"running\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"phase\": \"forking\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"recovered_run_id\": \"run-demo-recovered-fork\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"replay_comparison\": null") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"artifact_role\": \"recovered\"") == null);
}

test "buildReplayArtifactView exports fixture snapshot and ecosystem mapping" {
    const json = try replayArtifactJsonForTest(std.testing.allocator, .{
        .launched = true,
        .started_at_ms = 1_000,
        .recovered = true,
        .recovery_started_at_ms = 11_000,
    }, 19_000);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"artifact_kind\": \"nullhub.mission_control.replay\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"replay_fixture_path\": \"src/core/mission_control/code_red.v1.json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"snapshot\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"replay_comparison\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"artifact_kind\": \"nullhub.mission_control.run_replay\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"checkpoint_reused\": true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"replay_fixture\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"workflow_evidence\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"scanned_run_count\": 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ecosystem_mapping\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"nullwatch\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"trace_ref_source\": \"events[].trace\"") != null);
}

test "runtime commands enforce launch reset and recovery transitions" {
    const allocator = std.testing.allocator;
    var runtime = RuntimeState{};

    try std.testing.expect(canLaunch(runtime));
    try std.testing.expect(launch(&runtime, 1_000));
    try std.testing.expect(!canLaunch(runtime));
    try std.testing.expect(!launch(&runtime, 2_000));
    try std.testing.expect(!try recover(allocator, &runtime, 5_000));

    try std.testing.expect(try recover(allocator, &runtime, 11_000));
    try std.testing.expect(runtime.recovered);
    try std.testing.expect(!try recover(allocator, &runtime, 12_000));

    reset(&runtime);
    try std.testing.expect(canLaunch(runtime));
    try std.testing.expect(!runtime.recovered);
}
