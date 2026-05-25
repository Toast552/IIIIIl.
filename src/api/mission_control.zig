const std = @import("std");
const std_compat = @import("compat");
const helpers = @import("helpers.zig");
const query = @import("query.zig");
const mission = @import("../core/mission_control.zig");

const ApiResponse = helpers.ApiResponse;

const prefix = "/api/mission-control";

var mission_mutex: std_compat.sync.Mutex = .{};
var mission_runtime = mission.RuntimeState{};

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

    if (is_state) return stateResponse(allocator, now_ms);
    if (is_replay) return replayResponse(allocator, now_ms);

    if (is_reset) {
        mission.reset(&mission_runtime);
        return stateResponse(allocator, now_ms);
    }

    if (is_launch) {
        if (!mission.launch(&mission_runtime, now_ms)) return missionAlreadyStarted();
        return stateResponse(allocator, now_ms);
    }

    if (is_recover) {
        const recovered = mission.recover(allocator, &mission_runtime, now_ms) catch return helpers.serverError();
        if (!recovered) return missionNotRecoverable();
        return stateResponse(allocator, now_ms);
    }

    return helpers.notFound();
}

fn stateResponse(allocator: std.mem.Allocator, now_ms: i64) ApiResponse {
    const body = mission.buildStateJson(allocator, mission_runtime, now_ms) catch return helpers.serverError();
    return helpers.jsonOk(body);
}

fn replayResponse(allocator: std.mem.Allocator, now_ms: i64) ApiResponse {
    const body = mission.buildReplayArtifactJson(allocator, mission_runtime, now_ms) catch return helpers.serverError();
    return helpers.jsonOk(body);
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

test "isPath matches mission-control namespace" {
    try std.testing.expect(isPath("/api/mission-control/state"));
    try std.testing.expect(isPath("/api/mission-control/replay"));
    try std.testing.expect(isPath("/api/mission-control/reset"));
    try std.testing.expect(isPath("/api/mission-control/state?poll=1"));
    try std.testing.expect(!isPath("/api/observability/v1/runs"));
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
    const reset = handle(std.testing.allocator, "POST", "/api/mission-control/reset");
    defer std.testing.allocator.free(reset.body);

    const replay_resp = handle(std.testing.allocator, "GET", "/api/mission-control/replay");
    defer std.testing.allocator.free(replay_resp.body);

    try std.testing.expectEqualStrings("200 OK", replay_resp.status);
    try std.testing.expect(std.mem.indexOf(u8, replay_resp.body, "\"artifact_schema_version\": 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, replay_resp.body, "\"artifact_kind\": \"nullhub.mission_control.replay\"") != null);
}
