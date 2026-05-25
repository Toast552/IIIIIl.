const std = @import("std");
const std_compat = @import("compat");
const helpers = @import("helpers.zig");
const query = @import("query.zig");
const replay = @import("mission_control_replay.zig");

const ApiResponse = helpers.ApiResponse;

const prefix = "/api/mission-control";

const RuntimeState = struct {
    launched: bool = false,
    started_at_ms: i64 = 0,
    recovered: bool = false,
    recovery_started_at_ms: i64 = 0,
};

const MissionControls = struct {
    can_launch: bool,
    can_recover: bool,
    can_reset: bool,
};

const Agent = struct {
    id: []const u8,
    role: []const u8,
    status: []const u8,
    current_step: []const u8,
};

const GraphNode = struct {
    id: []const u8,
    label: []const u8,
    kind: []const u8,
    status: []const u8,
};

const GraphEdge = struct {
    from: []const u8,
    to: []const u8,
    status: []const u8,
};

const MissionGraph = struct {
    nodes: []const GraphNode,
    edges: []const GraphEdge,
};

const MissionEvent = struct {
    at_ms: i64,
    source: []const u8,
    level: []const u8,
    title: []const u8,
    detail: []const u8,
    status: []const u8,
    trace: ?replay.EventTraceDef,
};

const MissionTelemetry = struct {
    runs: usize,
    spans: usize,
    evals: usize,
    errors: usize,
    total_tokens: usize,
    total_cost_usd: f64,
    verdict: []const u8,
};

const FailurePanel = struct {
    run_id: []const u8,
    checkpoint_id: []const u8,
    failed_step: []const u8,
    error_message: []const u8,
    suggested_intervention: []const u8,
};

const RecoveryPanel = struct {
    run_id: []const u8,
    forked_from: []const u8,
    human_instruction: []const u8,
    status: []const u8,
};

const MissionSnapshot = struct {
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
    failure: ?FailurePanel,
    recovery: ?RecoveryPanel,
};

const ComponentMapping = struct {
    component: []const u8,
    role: []const u8,
    evidence: []const []const u8,
};

const WorkflowMapping = struct {
    component: []const u8,
    role: []const u8,
    checkpoint_id: []const u8,
    failed_run_id: []const u8,
    recovered_run_id: []const u8,
    human_instruction: []const u8,
    evidence: []const []const u8,
};

const ObservabilityMapping = struct {
    component: []const u8,
    role: []const u8,
    failed_run_id: []const u8,
    recovered_run_id: []const u8,
    trace_ref_source: []const u8,
    evidence: []const []const u8,
};

const ReplayArtifactMapping = struct {
    nulltickets: ComponentMapping,
    nullboiler: WorkflowMapping,
    nullclaw: ComponentMapping,
    nullwatch: ObservabilityMapping,
};

const ReplayArtifact = struct {
    artifact_schema_version: u8,
    artifact_kind: []const u8,
    generated_at_ms: i64,
    replay_fixture_path: []const u8,
    scenario_id: []const u8,
    scenario_version: []const u8,
    mode: []const u8,
    snapshot: MissionSnapshot,
    replay_fixture: replay.ReplayFixture,
    ecosystem_mapping: ReplayArtifactMapping,
};

var mission_mutex: std_compat.sync.Mutex = .{};
var mission_runtime = RuntimeState{};

pub fn isPath(target: []const u8) bool {
    const path = query.stripTarget(target);
    return std.mem.eql(u8, path, prefix) or std.mem.startsWith(u8, path, prefix ++ "/");
}

pub fn handle(allocator: std.mem.Allocator, method: []const u8, target: []const u8) ApiResponse {
    const path = query.stripTarget(target);
    if (!isPath(path)) return helpers.notFound();

    const is_state = std.mem.eql(u8, path, prefix ++ "/state");
    const is_replay = std.mem.eql(u8, path, prefix ++ "/replay");
    const is_reset = std.mem.eql(u8, path, prefix ++ "/reset");
    const is_launch = std.mem.eql(u8, path, prefix ++ "/launch");
    const is_recover = std.mem.eql(u8, path, prefix ++ "/recover");
    if (!is_state and !is_replay and !is_reset and !is_launch and !is_recover) return helpers.notFound();

    if (is_state or is_replay) {
        if (!std.mem.eql(u8, method, "GET")) return helpers.methodNotAllowed();
    } else if (!std.mem.eql(u8, method, "POST")) {
        return helpers.methodNotAllowed();
    }

    mission_mutex.lock();
    defer mission_mutex.unlock();

    const now_ms = std_compat.time.milliTimestamp();

    if (is_state) {
        const body = buildStateJson(allocator, mission_runtime, now_ms) catch return helpers.serverError();
        return helpers.jsonOk(body);
    }

    if (is_replay) {
        const body = buildReplayArtifactJson(allocator, mission_runtime, now_ms) catch return helpers.serverError();
        return helpers.jsonOk(body);
    }

    if (is_reset) {
        mission_runtime = .{};
        const body = buildStateJson(allocator, mission_runtime, now_ms) catch return helpers.serverError();
        return helpers.jsonOk(body);
    }

    var parsed = replay.parseValidated(allocator) catch return helpers.serverError();
    defer parsed.deinit();
    const elapsed_ms = elapsedSince(mission_runtime.started_at_ms, now_ms);
    const recovery_elapsed_ms = elapsedSince(mission_runtime.recovery_started_at_ms, now_ms);
    const phase = currentPhase(parsed.value, mission_runtime, elapsed_ms, recovery_elapsed_ms);

    if (is_launch) {
        if (!canLaunch(mission_runtime)) {
            return missionAlreadyStarted();
        }
        mission_runtime = .{
            .launched = true,
            .started_at_ms = now_ms,
        };
        const body = buildStateJson(allocator, mission_runtime, now_ms) catch return helpers.serverError();
        return helpers.jsonOk(body);
    }

    if (is_recover) {
        if (!canRecover(parsed.value, mission_runtime, phase)) {
            return missionNotRecoverable();
        }
        mission_runtime.recovered = true;
        mission_runtime.recovery_started_at_ms = now_ms;
        const body = buildStateJson(allocator, mission_runtime, now_ms) catch return helpers.serverError();
        return helpers.jsonOk(body);
    }

    return helpers.notFound();
}

fn missionAlreadyStarted() ApiResponse {
    return .{
        .status = "409 Conflict",
        .content_type = "application/json",
        .body = "{\"error\":{\"code\":\"mission_already_started\",\"message\":\"Mission is already started. Reset before launching again.\"}}",
    };
}

fn missionNotRecoverable() ApiResponse {
    return .{
        .status = "409 Conflict",
        .content_type = "application/json",
        .body = "{\"error\":{\"code\":\"mission_not_recoverable\",\"message\":\"Mission can only be recovered after the validation failure phase.\"}}",
    };
}

fn buildStateJson(allocator: std.mem.Allocator, runtime: RuntimeState, now_ms: i64) ![]u8 {
    var parsed = try replay.parseValidated(allocator);
    defer parsed.deinit();
    const fixture = parsed.value;

    const elapsed_ms = elapsedSince(runtime.started_at_ms, now_ms);
    const recovery_elapsed_ms = elapsedSince(runtime.recovery_started_at_ms, now_ms);
    const phase = currentPhase(fixture, runtime, elapsed_ms, recovery_elapsed_ms);
    const agents = try buildAgents(allocator, fixture, phase);
    defer allocator.free(agents);
    const nodes = try buildNodes(allocator, fixture, phase);
    defer allocator.free(nodes);
    const edges = try buildEdges(allocator, fixture, phase);
    defer allocator.free(edges);
    const events = try buildEvents(allocator, fixture, phase);
    defer allocator.free(events);
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
    );
    return std.json.Stringify.valueAlloc(allocator, snapshot, .{ .whitespace = .indent_2 });
}

fn buildReplayArtifactJson(allocator: std.mem.Allocator, runtime: RuntimeState, now_ms: i64) ![]u8 {
    var parsed = try replay.parseValidated(allocator);
    defer parsed.deinit();
    const fixture = parsed.value;

    const elapsed_ms = elapsedSince(runtime.started_at_ms, now_ms);
    const recovery_elapsed_ms = elapsedSince(runtime.recovery_started_at_ms, now_ms);
    const phase = currentPhase(fixture, runtime, elapsed_ms, recovery_elapsed_ms);
    const agents = try buildAgents(allocator, fixture, phase);
    defer allocator.free(agents);
    const nodes = try buildNodes(allocator, fixture, phase);
    defer allocator.free(nodes);
    const edges = try buildEdges(allocator, fixture, phase);
    defer allocator.free(edges);
    const events = try buildEvents(allocator, fixture, phase);
    defer allocator.free(events);
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
    );
    const artifact = ReplayArtifact{
        .artifact_schema_version = 1,
        .artifact_kind = "nullhub.mission_control.replay",
        .generated_at_ms = now_ms,
        .replay_fixture_path = "src/api/mission_control/code_red.v1.json",
        .scenario_id = fixture.scenario_id,
        .scenario_version = fixture.scenario_version,
        .mode = fixture.mode,
        .snapshot = snapshot,
        .replay_fixture = fixture,
        .ecosystem_mapping = replayArtifactMapping(fixture),
    };
    return std.json.Stringify.valueAlloc(allocator, artifact, .{ .whitespace = .indent_2 });
}

fn replayArtifactMapping(fixture: replay.ReplayFixture) ReplayArtifactMapping {
    return .{
        .nulltickets = .{
            .component = "nulltickets",
            .role = "Tracker-style task source and terminal workflow status.",
            .evidence = &.{ "events[source=nulltickets]", "graph.nodes[kind=tracker]" },
        },
        .nullboiler = .{
            .component = "nullboiler",
            .role = "Workflow orchestration, checkpointing, dispatch, and fork recovery.",
            .checkpoint_id = fixture.checkpoint_id,
            .failed_run_id = fixture.run_ids.failed,
            .recovered_run_id = fixture.run_ids.recovered,
            .human_instruction = fixture.human_instruction,
            .evidence = &.{ "phases", "graph.edges", "events[source=nullboiler]", "failure.checkpoint_id", "recovery.forked_from" },
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
) MissionSnapshot {
    const failed_visible = isAtOrAfter(fixture, phase, fixture.failure.visible_from_phase);
    const recovered_visible = runtime.recovered;
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

fn canLaunch(runtime: RuntimeState) bool {
    return !runtime.launched;
}

fn canRecover(fixture: replay.ReplayFixture, runtime: RuntimeState, phase: []const u8) bool {
    return runtime.launched and !runtime.recovered and std.mem.eql(u8, phase, fixture.failure.visible_from_phase);
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

test "isPath matches mission-control namespace" {
    try std.testing.expect(isPath("/api/mission-control/state"));
    try std.testing.expect(isPath("/api/mission-control/replay"));
    try std.testing.expect(isPath("/api/mission-control/reset"));
    try std.testing.expect(isPath("/api/mission-control/state?poll=1"));
    try std.testing.expect(!isPath("/api/observability/v1/runs"));
}

test "buildStateJson returns idle mission before launch" {
    const json = try buildStateJson(std.testing.allocator, .{}, 1_000);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"schema_version\": 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"mode\": \"deterministic_local_replay\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"scenario_id\": \"mission-code-red\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"status\": \"idle\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"phase\": \"idle\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"can_launch\": true") != null);
}

test "buildStateJson exposes failed mission and recover control" {
    const json = try buildStateJson(std.testing.allocator, .{
        .launched = true,
        .started_at_ms = 1_000,
    }, 11_000);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"status\": \"intervention_required\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"phase\": \"failed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"can_recover\": true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"trace_id\": \"trace-demo-code-red-primary\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"eval_key\": \"tool_success\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "zig build test exited with status 1") != null);
}

test "buildStateJson exposes recovered completed mission" {
    const json = try buildStateJson(std.testing.allocator, .{
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
}

test "buildReplayArtifactJson exports fixture snapshot and ecosystem mapping" {
    const json = try buildReplayArtifactJson(std.testing.allocator, .{
        .launched = true,
        .started_at_ms = 1_000,
        .recovered = true,
        .recovery_started_at_ms = 11_000,
    }, 19_000);
    defer std.testing.allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"artifact_kind\": \"nullhub.mission_control.replay\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"replay_fixture_path\": \"src/api/mission_control/code_red.v1.json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"snapshot\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"replay_fixture\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"ecosystem_mapping\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"nullwatch\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"trace_ref_source\": \"events[].trace\"") != null);
}

test "handle supports reset launch and recovery after failure" {
    const reset = handle(std.testing.allocator, "POST", "/api/mission-control/reset");
    defer std.testing.allocator.free(reset.body);
    try std.testing.expectEqualStrings("200 OK", reset.status);

    const launched = handle(std.testing.allocator, "POST", "/api/mission-control/launch");
    defer std.testing.allocator.free(launched.body);
    try std.testing.expectEqualStrings("200 OK", launched.status);
    try std.testing.expect(std.mem.indexOf(u8, launched.body, "\"status\": \"running\"") != null);

    mission_mutex.lock();
    mission_runtime = .{
        .launched = true,
        .started_at_ms = std_compat.time.milliTimestamp() - 10_000,
    };
    mission_mutex.unlock();

    const recovered = handle(std.testing.allocator, "POST", "/api/mission-control/recover");
    defer std.testing.allocator.free(recovered.body);
    try std.testing.expectEqualStrings("200 OK", recovered.status);
    try std.testing.expect(std.mem.indexOf(u8, recovered.body, "\"recovered_run_id\": \"run-demo-recovered-fork\"") != null);
}

test "handle rejects invalid mission transitions" {
    const reset = handle(std.testing.allocator, "POST", "/api/mission-control/reset");
    defer std.testing.allocator.free(reset.body);
    try std.testing.expectEqualStrings("200 OK", reset.status);

    const early_recover = handle(std.testing.allocator, "POST", "/api/mission-control/recover");
    try std.testing.expectEqualStrings("409 Conflict", early_recover.status);
    try std.testing.expect(std.mem.indexOf(u8, early_recover.body, "mission_not_recoverable") != null);

    const launched = handle(std.testing.allocator, "POST", "/api/mission-control/launch");
    defer std.testing.allocator.free(launched.body);
    try std.testing.expectEqualStrings("200 OK", launched.status);

    const duplicate_launch = handle(std.testing.allocator, "POST", "/api/mission-control/launch");
    try std.testing.expectEqualStrings("409 Conflict", duplicate_launch.status);
    try std.testing.expect(std.mem.indexOf(u8, duplicate_launch.body, "mission_already_started") != null);
}

test "handle returns clear status codes for unknown paths and methods" {
    const unknown_get = handle(std.testing.allocator, "GET", "/api/mission-control/nope");
    try std.testing.expectEqualStrings("404 Not Found", unknown_get.status);

    const wrong_method = handle(std.testing.allocator, "GET", "/api/mission-control/launch");
    try std.testing.expectEqualStrings("405 Method Not Allowed", wrong_method.status);

    const wrong_replay_method = handle(std.testing.allocator, "POST", "/api/mission-control/replay");
    try std.testing.expectEqualStrings("405 Method Not Allowed", wrong_replay_method.status);
}

test "handle returns replay artifact" {
    const replay_resp = handle(std.testing.allocator, "GET", "/api/mission-control/replay");
    defer std.testing.allocator.free(replay_resp.body);

    try std.testing.expectEqualStrings("200 OK", replay_resp.status);
    try std.testing.expect(std.mem.indexOf(u8, replay_resp.body, "\"artifact_schema_version\": 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, replay_resp.body, "\"artifact_kind\": \"nullhub.mission_control.replay\"") != null);
}
