const std = @import("std");
const http_proxy = @import("proxy.zig");
const query = @import("query.zig");

const Allocator = std.mem.Allocator;

const Response = http_proxy.Response;

const prefix = "/api/observability";

pub const Config = struct {
    watch_url: ?[]const u8 = null,
    watch_token: ?[]const u8 = null,
};

pub fn isProxyPath(target: []const u8) bool {
    return http_proxy.isPathInNamespace(target, prefix) or
        (target.len > prefix.len and
            std.mem.startsWith(u8, target, prefix) and
            target[prefix.len] == '?');
}

pub fn selectedWatchNameAlloc(allocator: Allocator, target: []const u8) !?[]u8 {
    return try query.valueAlloc(allocator, target, "nullhub_watch");
}

fn isSelectorParam(param: []const u8) bool {
    const key = if (std.mem.indexOfScalar(u8, param, '=')) |idx| param[0..idx] else param;
    return std.mem.eql(u8, key, "nullhub_watch");
}

fn stripSelectorParamsAlloc(allocator: Allocator, target: []const u8) ![]u8 {
    const qmark = std.mem.indexOfScalar(u8, target, '?') orelse return allocator.dupe(u8, target);

    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();
    try buf.appendSlice(target[0..qmark]);

    var wrote_query = false;
    var params = std.mem.splitScalar(u8, target[qmark + 1 ..], '&');
    while (params.next()) |param| {
        if (param.len == 0 or isSelectorParam(param)) continue;
        try buf.append(if (wrote_query) '&' else '?');
        wrote_query = true;
        try buf.appendSlice(param);
    }

    return buf.toOwnedSlice();
}

/// Proxies observability API requests to a managed or configured NullWatch instance.
/// The shared `/api/observability` prefix is stripped before forwarding, so
/// `/api/observability/v1/runs` becomes `/v1/runs` on NullWatch.
pub fn handle(allocator: Allocator, method: []const u8, target: []const u8, body: []const u8, cfg: Config) Response {
    if (!isProxyPath(target)) {
        return .{ .status = "404 Not Found", .content_type = "application/json", .body = "{\"error\":\"not found\"}" };
    }

    const base_url = cfg.watch_url orelse
        return .{ .status = "503 Service Unavailable", .content_type = "application/json", .body = "{\"error\":\"NullWatch not configured\"}" };

    const forward_target = stripSelectorParamsAlloc(allocator, target) catch
        return .{ .status = "500 Internal Server Error", .content_type = "application/json", .body = "{\"error\":\"internal error\"}" };
    defer allocator.free(forward_target);

    const proxied_path = forward_target[prefix.len..];
    const path = if (proxied_path.len == 0) "/v1/summary" else proxied_path;
    return http_proxy.forward(allocator, .{
        .method = method,
        .base_url = base_url,
        .path = path,
        .body = body,
        .bearer_token = cfg.watch_token,
        .unreachable_body = "{\"error\":\"NullWatch unreachable\"}",
    });
}

test "isProxyPath matches observability namespace" {
    try std.testing.expect(isProxyPath("/api/observability"));
    try std.testing.expect(isProxyPath("/api/observability?watch=default"));
    try std.testing.expect(isProxyPath("/api/observability/v1/runs"));
    try std.testing.expect(isProxyPath("/api/observability/health"));
    try std.testing.expect(!isProxyPath("/api/orchestration/v1/runs"));
}

test "handle returns not configured without NullWatch URL" {
    const resp = handle(std.testing.allocator, "GET", "/api/observability/v1/summary", "", .{});
    try std.testing.expectEqualStrings("503 Service Unavailable", resp.status);
    try std.testing.expectEqualStrings("{\"error\":\"NullWatch not configured\"}", resp.body);
}

test "handle rejects non-observability paths" {
    const resp = handle(std.testing.allocator, "GET", "/api/status", "", .{
        .watch_url = "http://127.0.0.1:7710",
    });
    try std.testing.expectEqualStrings("404 Not Found", resp.status);
}

test "selectedWatchNameAlloc reads hub selector query params" {
    const allocator = std.testing.allocator;
    const selected = (try selectedWatchNameAlloc(allocator, "/api/observability/v1/runs?limit=1&nullhub_watch=watch+one")).?;
    defer allocator.free(selected);
    try std.testing.expectEqualStrings("watch one", selected);
    try std.testing.expect((try selectedWatchNameAlloc(allocator, "/api/observability/v1/runs?watch=upstream")) == null);
}

test "stripSelectorParamsAlloc removes only NullHub watch selector" {
    const allocator = std.testing.allocator;
    const stripped = try stripSelectorParamsAlloc(allocator, "/api/observability/v1/runs?limit=50&nullhub_watch=alpha&status=ok");
    defer allocator.free(stripped);
    try std.testing.expectEqualStrings("/api/observability/v1/runs?limit=50&status=ok", stripped);

    const root = try stripSelectorParamsAlloc(allocator, "/api/observability?nullhub_watch=alpha");
    defer allocator.free(root);
    try std.testing.expectEqualStrings("/api/observability", root);

    const upstream_filter = try stripSelectorParamsAlloc(allocator, "/api/observability/v1/runs?watch=alpha&instance=demo");
    defer allocator.free(upstream_filter);
    try std.testing.expectEqualStrings("/api/observability/v1/runs?watch=alpha&instance=demo", upstream_filter);
}
