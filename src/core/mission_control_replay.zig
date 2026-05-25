const std = @import("std");

pub const expected_schema_version: u8 = 1;
pub const embedded_json = @embedFile("mission_control/code_red.v1.json");

pub const ReplayFixture = struct {
    schema_version: u8,
    mode: []const u8,
    scenario_id: []const u8,
    scenario_version: []const u8,
    title: []const u8,
    run_ids: RunIds,
    checkpoint_id: []const u8,
    human_instruction: []const u8,
    phases: []const PhaseDef,
    agents: []const AgentDef,
    graph: GraphDef,
    events: []const EventDef,
    telemetry: []const TelemetryDef,
    failure: FailureDef,
    recovery: RecoveryDef,
};

pub const RunIds = struct {
    failed: []const u8,
    recovered: []const u8,
};

pub const PhaseDef = struct {
    id: []const u8,
    track: []const u8,
    rank: u8,
    starts_at_ms: i64,
    status: []const u8,
    progress: u8,
    headline: []const u8,
};

pub const AgentDef = struct {
    id: []const u8,
    role: []const u8,
    active_phases: []const []const u8,
    done_after_phase: []const u8,
    blocked_phase: ?[]const u8,
    failed_phase: ?[]const u8,
    steps: []const AgentStepDef,
};

pub const AgentStepDef = struct {
    phase: []const u8,
    step: []const u8,
};

pub const GraphDef = struct {
    nodes: []const GraphNodeDef,
    edges: []const GraphEdgeDef,
};

pub const GraphNodeDef = struct {
    id: []const u8,
    label: []const u8,
    kind: []const u8,
    phase: []const u8,
    error_phase: ?[]const u8,
};

pub const GraphEdgeDef = struct {
    from: []const u8,
    to: []const u8,
    phase: []const u8,
    error_phase: ?[]const u8,
};

pub const EventDef = struct {
    at_ms: i64,
    phase: []const u8,
    source: []const u8,
    level: []const u8,
    title: []const u8,
    detail: []const u8,
    trace: ?EventTraceDef = null,
};

pub const EventTraceDef = struct {
    kind: []const u8,
    run_id: ?[]const u8 = null,
    trace_id: ?[]const u8 = null,
    span_id: ?[]const u8 = null,
    eval_key: ?[]const u8 = null,
    operation: []const u8,
};

pub const TelemetryDef = struct {
    phase: []const u8,
    runs: usize,
    spans: usize,
    evals: usize,
    errors: usize,
    total_tokens: usize,
    total_cost_usd: f64,
    verdict: []const u8,
};

pub const FailureDef = struct {
    visible_from_phase: []const u8,
    run_id: []const u8,
    checkpoint_id: []const u8,
    failed_step: []const u8,
    error_message: []const u8,
    suggested_intervention: []const u8,
};

pub const RecoveryDef = struct {
    visible_from_phase: []const u8,
    run_id: []const u8,
    forked_from: []const u8,
    human_instruction: []const u8,
};

pub const ValidationError = error{
    UnsupportedReplaySchema,
    InvalidReplayFixture,
    DuplicateReplayId,
    UnknownReplayReference,
    UnsortedReplayFixture,
};

pub fn parse(allocator: std.mem.Allocator) !std.json.Parsed(ReplayFixture) {
    return parseBytes(allocator, embedded_json);
}

pub fn parseBytes(allocator: std.mem.Allocator, bytes: []const u8) !std.json.Parsed(ReplayFixture) {
    return std.json.parseFromSlice(ReplayFixture, allocator, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = false,
    });
}

pub fn parseValidated(allocator: std.mem.Allocator) !std.json.Parsed(ReplayFixture) {
    var parsed = try parse(allocator);
    errdefer parsed.deinit();
    try validate(parsed.value);
    return parsed;
}

pub fn validate(fixture: ReplayFixture) ValidationError!void {
    if (fixture.schema_version != expected_schema_version) return error.UnsupportedReplaySchema;
    try requireNonEmpty(fixture.mode);
    try requireNonEmpty(fixture.scenario_id);
    try requireNonEmpty(fixture.scenario_version);
    try requireNonEmpty(fixture.title);
    try requireNonEmpty(fixture.run_ids.failed);
    try requireNonEmpty(fixture.run_ids.recovered);
    try requireNonEmpty(fixture.checkpoint_id);
    try requireNonEmpty(fixture.human_instruction);

    try validatePhases(fixture);
    try requirePhase(fixture, "idle");
    try requirePhase(fixture, "failed");
    try requirePhase(fixture, "completed");
    try validateAgents(fixture);
    try validateGraph(fixture);
    try validateEvents(fixture);
    try validateTelemetry(fixture);
    try validateFailure(fixture.failure, fixture);
    try validateRecovery(fixture.recovery, fixture);
}

pub fn phaseById(fixture: ReplayFixture, id: []const u8) ?PhaseDef {
    for (fixture.phases) |phase| {
        if (std.mem.eql(u8, phase.id, id)) return phase;
    }
    return null;
}

pub fn phaseRank(fixture: ReplayFixture, id: []const u8) ?u8 {
    return if (phaseById(fixture, id)) |phase| phase.rank else null;
}

fn validatePhases(fixture: ReplayFixture) ValidationError!void {
    if (fixture.phases.len == 0) return error.InvalidReplayFixture;

    for (fixture.phases, 0..) |phase, index| {
        try requireNonEmpty(phase.id);
        try requireNonEmpty(phase.track);
        try requireNonEmpty(phase.status);
        try requireNonEmpty(phase.headline);
        if (!isKnownTrack(phase.track)) return error.InvalidReplayFixture;
        if (phase.progress > 100) return error.InvalidReplayFixture;
        if (phase.starts_at_ms < 0) return error.InvalidReplayFixture;

        for (fixture.phases[0..index]) |previous| {
            if (std.mem.eql(u8, previous.id, phase.id)) return error.DuplicateReplayId;
            if (previous.rank == phase.rank) return error.DuplicateReplayId;
        }
    }

    try validateTrackOrdering(fixture, "primary");
    try validateTrackOrdering(fixture, "recovery");
}

fn validateTrackOrdering(fixture: ReplayFixture, track: []const u8) ValidationError!void {
    var seen = false;
    var last_start: i64 = 0;
    for (fixture.phases) |phase| {
        if (!std.mem.eql(u8, phase.track, track)) continue;
        if (seen and phase.starts_at_ms < last_start) return error.UnsortedReplayFixture;
        seen = true;
        last_start = phase.starts_at_ms;
    }
    if (!seen) return error.InvalidReplayFixture;
}

fn validateAgents(fixture: ReplayFixture) ValidationError!void {
    if (fixture.agents.len == 0) return error.InvalidReplayFixture;

    for (fixture.agents, 0..) |agent, index| {
        try requireNonEmpty(agent.id);
        try requireNonEmpty(agent.role);
        try requirePhase(fixture, agent.done_after_phase);
        if (agent.active_phases.len == 0) return error.InvalidReplayFixture;
        for (agent.active_phases) |phase| try requirePhase(fixture, phase);
        if (agent.blocked_phase) |phase| try requirePhase(fixture, phase);
        if (agent.failed_phase) |phase| try requirePhase(fixture, phase);
        for (agent.steps) |step| {
            try requirePhase(fixture, step.phase);
            try requireNonEmpty(step.step);
        }

        for (fixture.agents[0..index]) |previous| {
            if (std.mem.eql(u8, previous.id, agent.id)) return error.DuplicateReplayId;
        }
    }
}

fn validateGraph(fixture: ReplayFixture) ValidationError!void {
    if (fixture.graph.nodes.len == 0) return error.InvalidReplayFixture;

    for (fixture.graph.nodes, 0..) |node, index| {
        try requireNonEmpty(node.id);
        try requireNonEmpty(node.label);
        try requireNonEmpty(node.kind);
        try requirePhase(fixture, node.phase);
        if (node.error_phase) |phase| try requirePhase(fixture, phase);

        for (fixture.graph.nodes[0..index]) |previous| {
            if (std.mem.eql(u8, previous.id, node.id)) return error.DuplicateReplayId;
        }
    }

    for (fixture.graph.edges) |edge| {
        try requireNode(fixture, edge.from);
        try requireNode(fixture, edge.to);
        try requirePhase(fixture, edge.phase);
        if (edge.error_phase) |phase| try requirePhase(fixture, phase);
    }
}

fn validateEvents(fixture: ReplayFixture) ValidationError!void {
    if (fixture.events.len == 0) return error.InvalidReplayFixture;
    var last_at_ms: i64 = 0;
    for (fixture.events, 0..) |event, index| {
        if (event.at_ms < 0) return error.InvalidReplayFixture;
        if (index > 0 and event.at_ms < last_at_ms) return error.UnsortedReplayFixture;
        last_at_ms = event.at_ms;
        try requirePhase(fixture, event.phase);
        try requireNonEmpty(event.source);
        try requireNonEmpty(event.level);
        try requireNonEmpty(event.title);
        try requireNonEmpty(event.detail);
        if (event.trace) |trace| try validateEventTrace(trace, fixture);
    }
}

fn validateEventTrace(trace: EventTraceDef, fixture: ReplayFixture) ValidationError!void {
    try requireNonEmpty(trace.kind);
    try requireNonEmpty(trace.operation);
    if (!std.mem.eql(u8, trace.kind, "span") and !std.mem.eql(u8, trace.kind, "eval")) {
        return error.InvalidReplayFixture;
    }

    if (trace.run_id) |run_id| {
        try requireNonEmpty(run_id);
        try requireRun(fixture, run_id);
    }
    if (trace.trace_id) |trace_id| try requireNonEmpty(trace_id);
    if (trace.span_id) |span_id| try requireNonEmpty(span_id);
    if (trace.eval_key) |eval_key| try requireNonEmpty(eval_key);

    if (std.mem.eql(u8, trace.kind, "span") and trace.span_id == null) return error.InvalidReplayFixture;
    if (std.mem.eql(u8, trace.kind, "eval") and trace.eval_key == null) return error.InvalidReplayFixture;
}

fn validateTelemetry(fixture: ReplayFixture) ValidationError!void {
    if (fixture.telemetry.len == 0) return error.InvalidReplayFixture;
    for (fixture.telemetry) |entry| {
        try requirePhase(fixture, entry.phase);
        try requireNonEmpty(entry.verdict);
        if (entry.errors > entry.spans) return error.InvalidReplayFixture;
        if (entry.evals > entry.spans) return error.InvalidReplayFixture;
        if (entry.total_cost_usd < 0) return error.InvalidReplayFixture;
    }
}

fn validateFailure(failure: FailureDef, fixture: ReplayFixture) ValidationError!void {
    try requirePhase(fixture, failure.visible_from_phase);
    try requireNonEmpty(failure.run_id);
    try requireRun(fixture, failure.run_id);
    try requireNonEmpty(failure.checkpoint_id);
    try requireNonEmpty(failure.failed_step);
    try requireNode(fixture, failure.failed_step);
    try requireNonEmpty(failure.error_message);
    try requireNonEmpty(failure.suggested_intervention);
}

fn validateRecovery(recovery: RecoveryDef, fixture: ReplayFixture) ValidationError!void {
    try requirePhase(fixture, recovery.visible_from_phase);
    try requireNonEmpty(recovery.run_id);
    try requireRun(fixture, recovery.run_id);
    try requireNonEmpty(recovery.forked_from);
    try requireNonEmpty(recovery.human_instruction);
}

fn requirePhase(fixture: ReplayFixture, id: []const u8) ValidationError!void {
    if (phaseById(fixture, id) == null) return error.UnknownReplayReference;
}

fn requireNode(fixture: ReplayFixture, id: []const u8) ValidationError!void {
    for (fixture.graph.nodes) |node| {
        if (std.mem.eql(u8, node.id, id)) return;
    }
    return error.UnknownReplayReference;
}

fn requireRun(fixture: ReplayFixture, id: []const u8) ValidationError!void {
    if (std.mem.eql(u8, id, fixture.run_ids.failed)) return;
    if (std.mem.eql(u8, id, fixture.run_ids.recovered)) return;
    return error.UnknownReplayReference;
}

fn requireNonEmpty(value: []const u8) ValidationError!void {
    if (value.len == 0) return error.InvalidReplayFixture;
}

fn isKnownTrack(track: []const u8) bool {
    return std.mem.eql(u8, track, "idle") or
        std.mem.eql(u8, track, "primary") or
        std.mem.eql(u8, track, "recovery");
}

test "embedded mission replay fixture validates" {
    var parsed = try parseValidated(std.testing.allocator);
    defer parsed.deinit();

    try std.testing.expectEqual(@as(u8, expected_schema_version), parsed.value.schema_version);
    try std.testing.expectEqualStrings("mission-code-red", parsed.value.scenario_id);
    try std.testing.expect(phaseById(parsed.value, "completed") != null);
}

test "validate rejects duplicate phase ids" {
    const phases = [_]PhaseDef{
        .{ .id = "idle", .track = "idle", .rank = 0, .starts_at_ms = 0, .status = "idle", .progress = 0, .headline = "idle" },
        .{ .id = "failed", .track = "primary", .rank = 1, .starts_at_ms = 0, .status = "intervention_required", .progress = 60, .headline = "failed" },
        .{ .id = "failed", .track = "recovery", .rank = 2, .starts_at_ms = 0, .status = "completed", .progress = 100, .headline = "done" },
    };
    const fixture = minimalFixture(phases[0..], test_nodes[0..], test_edges[0..], test_events[0..], test_telemetry[0..]);
    try std.testing.expectError(error.DuplicateReplayId, validate(fixture));
}

test "validate rejects graph edges pointing at unknown nodes" {
    const edges = [_]GraphEdgeDef{
        .{ .from = "ticket", .to = "missing", .phase = "failed", .error_phase = null },
    };
    const fixture = minimalFixture(test_phases[0..], test_nodes[0..], edges[0..], test_events[0..], test_telemetry[0..]);
    try std.testing.expectError(error.UnknownReplayReference, validate(fixture));
}

test "validate rejects telemetry for unknown phases" {
    const telemetry = [_]TelemetryDef{
        .{ .phase = "missing", .runs = 1, .spans = 1, .evals = 0, .errors = 0, .total_tokens = 1, .total_cost_usd = 0.001, .verdict = "running" },
    };
    const fixture = minimalFixture(test_phases[0..], test_nodes[0..], test_edges[0..], test_events[0..], telemetry[0..]);
    try std.testing.expectError(error.UnknownReplayReference, validate(fixture));
}

test "validate rejects trace refs for unknown run ids" {
    const events = [_]EventDef{
        .{
            .at_ms = 0,
            .phase = "launching",
            .source = "nullwatch",
            .level = "info",
            .title = "event",
            .detail = "detail",
            .trace = .{
                .kind = "span",
                .run_id = "missing-run",
                .trace_id = "trace",
                .span_id = "span",
                .operation = "agent.step",
            },
        },
    };
    const fixture = minimalFixture(test_phases[0..], test_nodes[0..], test_edges[0..], events[0..], test_telemetry[0..]);
    try std.testing.expectError(error.UnknownReplayReference, validate(fixture));
}

test "validate rejects failure and recovery panels with unknown run ids" {
    var fixture = minimalFixture(test_phases[0..], test_nodes[0..], test_edges[0..], test_events[0..], test_telemetry[0..]);
    fixture.failure.run_id = "missing-failed-run";
    try std.testing.expectError(error.UnknownReplayReference, validate(fixture));

    fixture = minimalFixture(test_phases[0..], test_nodes[0..], test_edges[0..], test_events[0..], test_telemetry[0..]);
    fixture.recovery.run_id = "missing-recovered-run";
    try std.testing.expectError(error.UnknownReplayReference, validate(fixture));
}

test "validate rejects eval trace refs without eval keys" {
    const events = [_]EventDef{
        .{
            .at_ms = 0,
            .phase = "launching",
            .source = "nullwatch",
            .level = "info",
            .title = "event",
            .detail = "detail",
            .trace = .{
                .kind = "eval",
                .run_id = "failed-run",
                .trace_id = "trace",
                .span_id = "span",
                .operation = "eval.tool_success",
            },
        },
    };
    const fixture = minimalFixture(test_phases[0..], test_nodes[0..], test_edges[0..], events[0..], test_telemetry[0..]);
    try std.testing.expectError(error.InvalidReplayFixture, validate(fixture));
}

fn minimalFixture(
    phases: []const PhaseDef,
    nodes: []const GraphNodeDef,
    edges: []const GraphEdgeDef,
    events: []const EventDef,
    telemetry: []const TelemetryDef,
) ReplayFixture {
    return .{
        .schema_version = expected_schema_version,
        .mode = "deterministic_local_replay",
        .scenario_id = "test",
        .scenario_version = "v1",
        .title = "test",
        .run_ids = .{ .failed = "failed-run", .recovered = "recovered-run" },
        .checkpoint_id = "checkpoint",
        .human_instruction = "fix",
        .phases = phases,
        .agents = test_agents[0..],
        .graph = .{ .nodes = nodes, .edges = edges },
        .events = events,
        .telemetry = telemetry,
        .failure = .{
            .visible_from_phase = "failed",
            .run_id = "failed-run",
            .checkpoint_id = "checkpoint",
            .failed_step = "ticket",
            .error_message = "failed",
            .suggested_intervention = "recover",
        },
        .recovery = .{
            .visible_from_phase = "completed",
            .run_id = "recovered-run",
            .forked_from = "checkpoint",
            .human_instruction = "fix",
        },
    };
}

const test_phases = [_]PhaseDef{
    .{ .id = "idle", .track = "idle", .rank = 0, .starts_at_ms = 0, .status = "idle", .progress = 0, .headline = "idle" },
    .{ .id = "launching", .track = "primary", .rank = 1, .starts_at_ms = 0, .status = "running", .progress = 10, .headline = "launch" },
    .{ .id = "failed", .track = "primary", .rank = 2, .starts_at_ms = 100, .status = "intervention_required", .progress = 60, .headline = "failed" },
    .{ .id = "completed", .track = "recovery", .rank = 3, .starts_at_ms = 0, .status = "completed", .progress = 100, .headline = "done" },
};

const test_agent_steps = [_]AgentStepDef{
    .{ .phase = "failed", .step = "work" },
};

const test_agents = [_]AgentDef{
    .{
        .id = "agent",
        .role = "coder",
        .active_phases = &.{"failed"},
        .done_after_phase = "failed",
        .blocked_phase = null,
        .failed_phase = null,
        .steps = test_agent_steps[0..],
    },
};

const test_nodes = [_]GraphNodeDef{
    .{ .id = "ticket", .label = "Ticket", .kind = "tracker", .phase = "launching", .error_phase = null },
};

const test_edges = [_]GraphEdgeDef{};

const test_events = [_]EventDef{
    .{ .at_ms = 0, .phase = "launching", .source = "test", .level = "info", .title = "event", .detail = "detail" },
};

const test_telemetry = [_]TelemetryDef{
    .{ .phase = "idle", .runs = 0, .spans = 0, .evals = 0, .errors = 0, .total_tokens = 0, .total_cost_usd = 0, .verdict = "idle" },
};
