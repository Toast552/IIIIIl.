const std = @import("std");
const std_compat = @import("compat");
const durable_file = @import("durable_file.zig");
const mission_core = @import("mission_control.zig");
const replay_fixture = @import("mission_control_replay.zig");
const paths_mod = @import("paths.zig");

pub const max_artifact_bytes: usize = 8 * 1024 * 1024;
const extension = ".json";

pub const Metadata = struct {
    generated_at_ms: i64,
    scenario_id: []const u8,
    scenario_version: []const u8,
    mission_id: []const u8,
    title: []const u8,
    status: []const u8,
    phase: []const u8,
    artifact_kind: []const u8,
};

pub const Record = struct {
    id: []const u8,
    saved_at_ms: i64,
    generated_at_ms: i64,
    scenario_id: []const u8,
    scenario_version: []const u8,
    mission_id: []const u8,
    title: []const u8,
    status: []const u8,
    phase: []const u8,
    artifact_kind: []const u8,
    artifact_path: []const u8,
    size_bytes: usize,

    pub fn deinit(self: Record, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.scenario_id);
        allocator.free(self.scenario_version);
        allocator.free(self.mission_id);
        allocator.free(self.title);
        allocator.free(self.status);
        allocator.free(self.phase);
        allocator.free(self.artifact_kind);
        allocator.free(self.artifact_path);
    }
};

const ReplayCandidate = struct {
    name: []u8,
    saved_at_ms: i64,
    size_bytes: usize,

    fn deinit(self: ReplayCandidate, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }

    fn id(self: ReplayCandidate) []const u8 {
        return self.name[0 .. self.name.len - extension.len];
    }
};

pub fn save(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    saved_at_ms: i64,
    artifact_json: []const u8,
) !Record {
    if (artifact_json.len > max_artifact_bytes) return error.ArtifactTooLarge;
    var parsed = try parseValidatedReplayArtifact(allocator, artifact_json);
    defer parsed.deinit();
    const metadata = metadataFromArtifact(parsed.value);

    const dir_path = try ensureReplayDir(allocator, paths);
    defer allocator.free(dir_path);

    const id = try buildReplayId(allocator, saved_at_ms, metadata.scenario_id, metadata.phase);
    defer allocator.free(id);
    const filename = try std.fmt.allocPrint(allocator, "{s}{s}", .{ id, extension });
    defer allocator.free(filename);
    const artifact_path = try std.fs.path.join(allocator, &.{ dir_path, filename });
    defer allocator.free(artifact_path);

    try writeArtifactAtomic(allocator, artifact_path, artifact_json);

    return recordFromMetadata(allocator, id, saved_at_ms, metadata, artifact_json.len + 1);
}

pub fn list(allocator: std.mem.Allocator, paths: paths_mod.Paths, limit: usize) ![]Record {
    const dir_path = try paths.missionReplayDir(allocator);
    defer allocator.free(dir_path);

    var dir = std_compat.fs.openDirAbsolute(dir_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return allocator.alloc(Record, 0),
        else => return err,
    };
    defer dir.close();

    var candidates: std.ArrayListUnmanaged(ReplayCandidate) = .empty;
    defer {
        for (candidates.items) |candidate| candidate.deinit(allocator);
        candidates.deinit(allocator);
    }

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, extension)) continue;

        const id = entry.name[0 .. entry.name.len - extension.len];
        if (!isValidReplayId(id)) continue;

        const stat = dir.statFile(entry.name) catch continue;
        const name = try allocator.dupe(u8, entry.name);
        errdefer allocator.free(name);
        try candidates.append(allocator, .{
            .name = name,
            .saved_at_ms = parseSavedAtFromId(id) orelse 0,
            .size_bytes = @intCast(stat.size),
        });
    }

    std.mem.sort(ReplayCandidate, candidates.items, {}, candidateNewerFirst);

    var records: std.ArrayListUnmanaged(Record) = .empty;
    errdefer for (records.items) |record| record.deinit(allocator);
    defer records.deinit(allocator);

    for (candidates.items) |candidate| {
        if (limit != 0 and records.items.len >= limit) break;

        const artifact_json = dir.readFileAlloc(allocator, candidate.name, max_artifact_bytes) catch continue;
        defer allocator.free(artifact_json);

        var record = recordFromArtifactJson(allocator, candidate.id(), artifact_json, candidate.size_bytes) catch continue;
        errdefer record.deinit(allocator);
        try records.append(allocator, record);
    }

    return try records.toOwnedSlice(allocator);
}

pub fn read(allocator: std.mem.Allocator, paths: paths_mod.Paths, id: []const u8) ![]u8 {
    if (!isValidReplayId(id)) return error.InvalidReplayId;

    const dir_path = try paths.missionReplayDir(allocator);
    defer allocator.free(dir_path);
    const filename = try std.fmt.allocPrint(allocator, "{s}{s}", .{ id, extension });
    defer allocator.free(filename);
    const artifact_path = try std.fs.path.join(allocator, &.{ dir_path, filename });
    defer allocator.free(artifact_path);

    const file = try std_compat.fs.openFileAbsolute(artifact_path, .{});
    defer file.close();
    const artifact_json = try file.readToEndAlloc(allocator, max_artifact_bytes);
    errdefer allocator.free(artifact_json);
    var parsed = try parseValidatedReplayArtifact(allocator, artifact_json);
    defer parsed.deinit();
    return artifact_json;
}

pub fn deinitRecords(allocator: std.mem.Allocator, records: []Record) void {
    for (records) |record| record.deinit(allocator);
    allocator.free(records);
}

fn recordFromMetadata(allocator: std.mem.Allocator, id: []const u8, saved_at_ms: i64, metadata: Metadata, size_bytes: usize) !Record {
    const owned_id = try allocator.dupe(u8, id);
    errdefer allocator.free(owned_id);
    const scenario_id = try allocator.dupe(u8, metadata.scenario_id);
    errdefer allocator.free(scenario_id);
    const scenario_version = try allocator.dupe(u8, metadata.scenario_version);
    errdefer allocator.free(scenario_version);
    const mission_id = try allocator.dupe(u8, metadata.mission_id);
    errdefer allocator.free(mission_id);
    const title = try allocator.dupe(u8, metadata.title);
    errdefer allocator.free(title);
    const status = try allocator.dupe(u8, metadata.status);
    errdefer allocator.free(status);
    const phase = try allocator.dupe(u8, metadata.phase);
    errdefer allocator.free(phase);
    const artifact_kind = try allocator.dupe(u8, metadata.artifact_kind);
    errdefer allocator.free(artifact_kind);
    const artifact_path = try std.fmt.allocPrint(allocator, "mission-control/replays/{s}{s}", .{ id, extension });
    errdefer allocator.free(artifact_path);

    return .{
        .id = owned_id,
        .saved_at_ms = saved_at_ms,
        .generated_at_ms = metadata.generated_at_ms,
        .scenario_id = scenario_id,
        .scenario_version = scenario_version,
        .mission_id = mission_id,
        .title = title,
        .status = status,
        .phase = phase,
        .artifact_kind = artifact_kind,
        .artifact_path = artifact_path,
        .size_bytes = size_bytes,
    };
}

fn recordFromArtifactJson(allocator: std.mem.Allocator, id: []const u8, artifact_json: []const u8, size_bytes: usize) !Record {
    var parsed = try parseValidatedReplayArtifact(allocator, artifact_json);
    defer parsed.deinit();
    return recordFromArtifact(allocator, id, parsed.value, size_bytes);
}

fn parseValidatedReplayArtifact(allocator: std.mem.Allocator, artifact_json: []const u8) !std.json.Parsed(mission_core.ReplayArtifact) {
    var parsed = try std.json.parseFromSlice(mission_core.ReplayArtifact, allocator, artifact_json, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = false,
    });
    errdefer parsed.deinit();
    try validateReplayArtifact(parsed.value);
    return parsed;
}

fn validateReplayArtifact(artifact: mission_core.ReplayArtifact) !void {
    if (artifact.artifact_schema_version != 1) return error.InvalidReplayArtifact;
    if (!std.mem.eql(u8, artifact.artifact_kind, "nullhub.mission_control.replay")) return error.InvalidReplayArtifact;
    if (artifact.generated_at_ms <= 0) return error.InvalidReplayArtifact;
    if (!std.mem.eql(u8, artifact.scenario_id, artifact.replay_fixture.scenario_id)) return error.InvalidReplayArtifact;
    if (!std.mem.eql(u8, artifact.scenario_version, artifact.replay_fixture.scenario_version)) return error.InvalidReplayArtifact;
    if (!std.mem.eql(u8, artifact.snapshot.scenario_id, artifact.scenario_id)) return error.InvalidReplayArtifact;
    if (!std.mem.eql(u8, artifact.snapshot.scenario_version, artifact.scenario_version)) return error.InvalidReplayArtifact;
    if (!std.mem.eql(u8, artifact.workflow_evidence.status, artifact.snapshot.workflow_evidence.status)) return error.InvalidReplayArtifact;
    replay_fixture.validate(artifact.replay_fixture) catch return error.InvalidReplayArtifact;
}

fn metadataFromArtifact(artifact: mission_core.ReplayArtifact) Metadata {
    return .{
        .generated_at_ms = artifact.generated_at_ms,
        .scenario_id = artifact.scenario_id,
        .scenario_version = artifact.scenario_version,
        .mission_id = artifact.snapshot.mission_id,
        .title = artifact.snapshot.title,
        .status = artifact.snapshot.status,
        .phase = artifact.snapshot.phase,
        .artifact_kind = artifact.artifact_kind,
    };
}

fn recordFromArtifact(allocator: std.mem.Allocator, id: []const u8, artifact: mission_core.ReplayArtifact, size_bytes: usize) !Record {
    const metadata = metadataFromArtifact(artifact);
    return recordFromMetadata(allocator, id, parseSavedAtFromId(id) orelse artifact.generated_at_ms, metadata, size_bytes);
}

fn writeArtifactAtomic(allocator: std.mem.Allocator, artifact_path: []const u8, artifact_json: []const u8) !void {
    try durable_file.writeTextFileAtomically(allocator, artifact_path, artifact_json);
}

fn ensureReplayDir(allocator: std.mem.Allocator, paths: paths_mod.Paths) ![]const u8 {
    std_compat.fs.makeDirAbsolute(paths.root) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const mission_dir = try std.fs.path.join(allocator, &.{ paths.root, "mission-control" });
    defer allocator.free(mission_dir);
    std_compat.fs.makeDirAbsolute(mission_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    const dir_path = try paths.missionReplayDir(allocator);
    errdefer allocator.free(dir_path);
    std_compat.fs.makeDirAbsolute(dir_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    return dir_path;
}

fn buildReplayId(allocator: std.mem.Allocator, saved_at_ms: i64, scenario_id: []const u8, phase: []const u8) ![]u8 {
    const scenario = try sanitizeIdPart(allocator, scenario_id);
    defer allocator.free(scenario);
    const phase_part = try sanitizeIdPart(allocator, phase);
    defer allocator.free(phase_part);
    return std.fmt.allocPrint(allocator, "{d}-{s}-{s}-{x}", .{
        saved_at_ms,
        scenario,
        phase_part,
        std_compat.crypto.random.int(u64),
    });
}

fn sanitizeIdPart(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);
    var last_dash = false;
    for (value) |byte| {
        const safe = std.ascii.isAlphanumeric(byte) or byte == '.' or byte == '_' or byte == '-';
        const ch: u8 = if (safe) std.ascii.toLower(byte) else '-';
        if (ch == '-') {
            if (last_dash) continue;
            last_dash = true;
        } else {
            last_dash = false;
        }
        try out.append(allocator, ch);
        if (out.items.len >= 64) break;
    }
    if (out.items.len == 0) try out.appendSlice(allocator, "mission");
    while (out.items.len > 1 and out.items[out.items.len - 1] == '-') {
        _ = out.pop();
    }
    return try out.toOwnedSlice(allocator);
}

fn isValidReplayId(id: []const u8) bool {
    if (id.len == 0 or id.len > 180) return false;
    for (id) |byte| {
        if (!(std.ascii.isAlphanumeric(byte) or byte == '.' or byte == '_' or byte == '-')) return false;
    }
    return true;
}

fn parseSavedAtFromId(id: []const u8) ?i64 {
    const dash = std.mem.indexOfScalar(u8, id, '-') orelse return null;
    return std.fmt.parseInt(i64, id[0..dash], 10) catch null;
}

fn candidateNewerFirst(_: void, a: ReplayCandidate, b: ReplayCandidate) bool {
    if (a.saved_at_ms == b.saved_at_ms) return std.mem.order(u8, a.id(), b.id()) == .gt;
    return a.saved_at_ms > b.saved_at_ms;
}

test "mission replay store saves lists and reads artifacts" {
    const test_helpers = @import("../test_helpers.zig");
    const allocator = std.testing.allocator;
    var fixture = try test_helpers.TempPaths.init(allocator);
    defer fixture.deinit();

    var view = try mission_core.buildReplayArtifactViewWithEvidence(allocator, .{
        .launched = true,
        .started_at_ms = 1_000,
        .recovered = true,
        .recovery_started_at_ms = 11_000,
    }, 20_000, replayEvidenceForTest());
    defer view.deinit(allocator);
    const artifact = try std.json.Stringify.valueAlloc(allocator, view.artifact, .{ .whitespace = .indent_2 });
    defer allocator.free(artifact);

    var record = try save(allocator, fixture.paths, 20_000, artifact);
    defer record.deinit(allocator);
    try std.testing.expect(std.mem.startsWith(u8, record.id, "20000-mission-code-red-completed-"));

    const body = try read(allocator, fixture.paths, record.id);
    defer allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"scenario_id\": \"mission-code-red\"") != null);

    const records = try list(allocator, fixture.paths, 10);
    defer deinitRecords(allocator, records);
    try std.testing.expectEqual(@as(usize, 1), records.len);
    try std.testing.expectEqualStrings(record.id, records[0].id);
    try std.testing.expectEqualStrings("completed", records[0].phase);
}

fn replayEvidenceForTest() mission_core.WorkflowEvidence {
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

test "mission replay store list and read do not create replay directories" {
    const test_helpers = @import("../test_helpers.zig");
    const allocator = std.testing.allocator;
    var fixture = try test_helpers.TempPaths.init(allocator);
    defer fixture.deinit();

    const records = try list(allocator, fixture.paths, 10);
    defer deinitRecords(allocator, records);
    try std.testing.expectEqual(@as(usize, 0), records.len);

    const mission_dir = try fixture.path(allocator, "mission-control");
    defer allocator.free(mission_dir);
    try std.testing.expectError(error.FileNotFound, std_compat.fs.accessAbsolute(mission_dir, .{}));

    try std.testing.expectError(
        error.FileNotFound,
        read(allocator, fixture.paths, "1234-mission-code-red-completed-deadbeef"),
    );
}

test "mission replay store rejects corrupted persisted artifact reads" {
    const test_helpers = @import("../test_helpers.zig");
    const allocator = std.testing.allocator;
    var fixture = try test_helpers.TempPaths.init(allocator);
    defer fixture.deinit();

    const replay_dir = try ensureReplayDir(allocator, fixture.paths);
    defer allocator.free(replay_dir);
    const bad_path = try std.fs.path.join(allocator, &.{ replay_dir, "1234-mission-code-red-completed-deadbeef.json" });
    defer allocator.free(bad_path);

    var file = try std_compat.fs.createFileAbsolute(bad_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll("{\"artifact_kind\":\"wrong\"}");

    try std.testing.expectError(
        error.InvalidReplayArtifact,
        read(allocator, fixture.paths, "1234-mission-code-red-completed-deadbeef"),
    );
}
