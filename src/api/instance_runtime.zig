const std = @import("std");
const std_compat = @import("compat");
const state_mod = @import("../core/state.zig");
const manager_mod = @import("../supervisor/manager.zig");
const paths_mod = @import("../core/paths.zig");
const health_mod = @import("../supervisor/health.zig");
const registry = @import("../installer/registry.zig");

pub const Snapshot = struct {
    status: manager_mod.Status,
    pid: ?std_compat.process.Child.Id = null,
    uptime_seconds: ?u64 = null,
    restart_count: u32 = 0,
    port: u16 = 0,
};

fn snapshotFromManager(status: manager_mod.InstanceStatus) Snapshot {
    return .{
        .status = status.status,
        .pid = status.pid,
        .uptime_seconds = status.uptime_seconds,
        .restart_count = status.restart_count,
        .port = status.port,
    };
}

/// Read a port value from an instance's config.json using a dot-separated key
/// (e.g. "gateway.port" -> config["gateway"]["port"]).
pub fn readPortFromConfig(allocator: std.mem.Allocator, paths: paths_mod.Paths, component: []const u8, name: []const u8, dot_key: []const u8) ?u16 {
    const config_path = paths.instanceConfig(allocator, component, name) catch return null;
    defer allocator.free(config_path);

    const file = std_compat.fs.openFileAbsolute(config_path, .{}) catch return null;
    defer file.close();
    const contents = file.readToEndAlloc(allocator, 4 * 1024 * 1024) catch return null;
    defer allocator.free(contents);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, contents, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return null;
    defer parsed.deinit();

    var current = parsed.value;
    var it = std.mem.splitScalar(u8, dot_key, '.');
    while (it.next()) |segment| {
        switch (current) {
            .object => |obj| current = obj.get(segment) orelse return null,
            else => return null,
        }
    }

    return parsePortValue(current);
}

fn parsePortValue(value: std.json.Value) ?u16 {
    return switch (value) {
        .integer => |raw| if (raw >= 0 and raw <= 65535) @intCast(raw) else null,
        .number_string => |raw| std.fmt.parseInt(u16, raw, 10) catch null,
        .string => |raw| std.fmt.parseInt(u16, raw, 10) catch null,
        else => null,
    };
}

fn readStringFromConfig(allocator: std.mem.Allocator, paths: paths_mod.Paths, component: []const u8, name: []const u8, dot_key: []const u8) ?[]u8 {
    const config_path = paths.instanceConfig(allocator, component, name) catch return null;
    defer allocator.free(config_path);

    const file = std_compat.fs.openFileAbsolute(config_path, .{}) catch return null;
    defer file.close();
    const contents = file.readToEndAlloc(allocator, 4 * 1024 * 1024) catch return null;
    defer allocator.free(contents);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, contents, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return null;
    defer parsed.deinit();

    var current = parsed.value;
    var it = std.mem.splitScalar(u8, dot_key, '.');
    while (it.next()) |segment| {
        switch (current) {
            .object => |obj| current = obj.get(segment) orelse return null,
            else => return null,
        }
    }

    if (current != .string) return null;
    return allocator.dupe(u8, current.string) catch null;
}

fn normalizeHealthHost(allocator: std.mem.Allocator, host: []const u8) ![]u8 {
    if (host.len == 0 or
        std.mem.eql(u8, host, "0.0.0.0") or
        std.mem.eql(u8, host, "::") or
        std.mem.eql(u8, host, "localhost"))
    {
        return allocator.dupe(u8, "127.0.0.1");
    }
    return allocator.dupe(u8, host);
}

fn isImportedStandalone(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
    entry: state_mod.InstanceEntry,
) bool {
    const known = registry.findKnownComponent(component) orelse return false;
    if (standalonePortConfigKey(component) == null) return false;
    if (!isStandaloneLaunchMode(component, entry.launch_mode, known.default_launch_command)) return false;

    const inst_dir = paths.instanceDir(allocator, component, name) catch return false;
    defer allocator.free(inst_dir);
    const real_dir = std_compat.fs.realpathAlloc(allocator, inst_dir) catch return false;
    defer allocator.free(real_dir);

    const home = std_compat.process.getEnvVarOwned(allocator, "HOME") catch
        std_compat.process.getEnvVarOwned(allocator, "USERPROFILE") catch return false;
    defer allocator.free(home);
    const standalone_root = std.fmt.allocPrint(allocator, "{s}/.{s}", .{ home, component }) catch return false;
    defer allocator.free(standalone_root);
    const real_standalone_root = std_compat.fs.realpathAlloc(allocator, standalone_root) catch return false;
    defer allocator.free(real_standalone_root);

    return std.mem.eql(u8, real_dir, real_standalone_root);
}

fn standalonePortConfigKey(component: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, component, "nullclaw")) return "gateway.port";
    if (std.mem.eql(u8, component, "nullwatch") or
        std.mem.eql(u8, component, "nullboiler") or
        std.mem.eql(u8, component, "nulltickets"))
    {
        return "port";
    }
    return null;
}

fn isStandaloneLaunchMode(component: []const u8, launch_mode: []const u8, default_launch_mode: []const u8) bool {
    if (standalonePortConfigKey(component) == null) return false;
    if (std.mem.eql(u8, launch_mode, default_launch_mode)) return true;
    if ((std.mem.eql(u8, component, "nullboiler") or std.mem.eql(u8, component, "nulltickets")) and
        (std.mem.eql(u8, launch_mode, component) or std.mem.eql(u8, launch_mode, "serve")))
    {
        return true;
    }
    if (std.mem.eql(u8, component, "nullwatch")) {
        return std.mem.eql(u8, launch_mode, "gateway") or
            std.mem.eql(u8, launch_mode, "nullwatch");
    }
    return false;
}

fn standaloneStatus(manager_snapshot: ?Snapshot, live_ok: bool) manager_mod.Status {
    if (live_ok) return .running;
    if (manager_snapshot) |snapshot| {
        return switch (snapshot.status) {
            .starting, .restarting, .stopping => snapshot.status,
            .running, .failed, .stopped => .stopped,
        };
    }
    return .stopped;
}

fn deriveImportedStandaloneSnapshot(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
    entry: state_mod.InstanceEntry,
    manager_snapshot: ?Snapshot,
) ?Snapshot {
    if (!isImportedStandalone(allocator, paths, component, name, entry)) return null;

    const known = registry.findKnownComponent(component) orelse return null;
    const port_key = standalonePortConfigKey(component) orelse return null;
    const port = readPortFromConfig(allocator, paths, component, name, port_key) orelse
        readPortFromConfig(allocator, paths, component, name, "gateway.port") orelse
        readPortFromConfig(allocator, paths, component, name, "port") orelse
        known.default_port;
    if (port == 0) return null;

    const configured_host = readStringFromConfig(allocator, paths, component, name, "host") orelse
        allocator.dupe(u8, "127.0.0.1") catch return null;
    defer allocator.free(configured_host);
    const health_host = normalizeHealthHost(allocator, configured_host) catch return null;
    defer allocator.free(health_host);

    const health = health_mod.check(allocator, health_host, port, known.default_health_endpoint);
    const status = standaloneStatus(manager_snapshot, health.ok);
    var snapshot = manager_snapshot orelse Snapshot{ .status = status };
    snapshot.status = status;
    snapshot.port = port;
    if (status == .stopped) {
        snapshot.pid = null;
        snapshot.uptime_seconds = null;
    }
    return snapshot;
}

pub fn resolve(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    manager: *manager_mod.Manager,
    component: []const u8,
    name: []const u8,
    entry: state_mod.InstanceEntry,
) Snapshot {
    const manager_snapshot = if (manager.getStatus(component, name)) |status| snapshotFromManager(status) else null;
    if (deriveImportedStandaloneSnapshot(allocator, paths, component, name, entry, manager_snapshot)) |snapshot| return snapshot;
    return manager_snapshot orelse .{ .status = .stopped };
}

test "standalone runtime metadata covers nullclaw and nullwatch" {
    try std.testing.expectEqualStrings("gateway.port", standalonePortConfigKey("nullclaw").?);
    try std.testing.expectEqualStrings("port", standalonePortConfigKey("nullwatch").?);
    try std.testing.expectEqualStrings("port", standalonePortConfigKey("nullboiler").?);
    try std.testing.expectEqualStrings("port", standalonePortConfigKey("nulltickets").?);

    try std.testing.expect(isStandaloneLaunchMode("nullclaw", "gateway", "gateway"));
    try std.testing.expect(isStandaloneLaunchMode("nullwatch", "serve", "serve"));
    try std.testing.expect(isStandaloneLaunchMode("nullwatch", "gateway", "serve"));
    try std.testing.expect(isStandaloneLaunchMode("nullwatch", "nullwatch", "serve"));
    try std.testing.expect(isStandaloneLaunchMode("nullboiler", "server", "server"));
    try std.testing.expect(isStandaloneLaunchMode("nullboiler", "nullboiler", "server"));
    try std.testing.expect(isStandaloneLaunchMode("nulltickets", "serve", "server"));
    try std.testing.expect(!isStandaloneLaunchMode("nullboiler", "gateway", "server"));
}

test "readPortFromConfig accepts string ports" {
    const allocator = std.testing.allocator;
    var fixture = try @import("../test_helpers.zig").TempPaths.init(allocator);
    defer fixture.deinit();
    try fixture.paths.ensureDirs();

    const inst_dir = try fixture.paths.instanceDir(allocator, "nullwatch", "watch");
    defer allocator.free(inst_dir);
    try std_compat.fs.makeDirAbsolute(std.fs.path.dirname(inst_dir).?);
    try std_compat.fs.makeDirAbsolute(inst_dir);

    const config_path = try fixture.paths.instanceConfig(allocator, "nullwatch", "watch");
    defer allocator.free(config_path);
    const file = try std_compat.fs.createFileAbsolute(config_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll("{\"port\":\"7711\",\"host\":\"::1\"}");

    try std.testing.expectEqual(@as(u16, 7711), readPortFromConfig(allocator, fixture.paths, "nullwatch", "watch", "port").?);

    const host = readStringFromConfig(allocator, fixture.paths, "nullwatch", "watch", "host").?;
    defer allocator.free(host);
    try std.testing.expectEqualStrings("::1", host);

    const normalized = try normalizeHealthHost(allocator, "::");
    defer allocator.free(normalized);
    try std.testing.expectEqualStrings("127.0.0.1", normalized);
}
