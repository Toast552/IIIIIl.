const std = @import("std");
const http_proxy = @import("proxy.zig");
const query = @import("query.zig");

const Allocator = std.mem.Allocator;

const Response = http_proxy.Response;

const prefix = "/api/nullwatch";

pub const Config = struct {
    watch_url: ?[]const u8 = null,
    watch_token: ?[]const u8 = null,
};

pub fn isProxyPath(target: []const u8) bool {
    return http_proxy.isTargetInNamespace(target, prefix);
}

pub fn selectedWatchNameAlloc(allocator: Allocator, target: []const u8) !?[]u8 {
    return try query.valueAlloc(allocator, target, "nullhub_watch");
}

/// Proxies NullWatch API requests to a managed or configured NullWatch instance.
/// The shared `/api/nullwatch` prefix is stripped before forwarding, so
/// `/api/nullwatch/v1/runs` becomes `/v1/runs` on NullWatch.
pub fn handle(allocator: Allocator, method: []const u8, target: []const u8, body: []const u8, cfg: Config) Response {
    if (!isProxyPath(target)) {
        return .{ .status = "404 Not Found", .content_type = "application/json", .body = "{\"error\":\"not found\"}" };
    }

    const base_url = cfg.watch_url orelse
        return .{ .status = "503 Service Unavailable", .content_type = "application/json", .body = "{\"error\":\"NullWatch not configured\"}" };

    const selector_params = [_][]const u8{"nullhub_watch"};
    var forwarded = http_proxy.rewriteProductProxyTarget(allocator, target, .{
        .prefix = prefix,
        .selector_params = selector_params[0..],
        .default_path = "/v1/summary",
    }) catch
        return .{ .status = "500 Internal Server Error", .content_type = "application/json", .body = "{\"error\":\"internal error\"}" };
    defer forwarded.deinit(allocator);

    return http_proxy.forward(allocator, .{
        .method = method,
        .base_url = base_url,
        .path = forwarded.path,
        .body = body,
        .bearer_token = cfg.watch_token,
        .unreachable_body = "{\"error\":\"NullWatch unreachable\"}",
    });
}

test "isProxyPath matches NullWatch namespace" {
    try std.testing.expect(isProxyPath("/api/nullwatch"));
    try std.testing.expect(isProxyPath("/api/nullwatch?watch=default"));
    try std.testing.expect(isProxyPath("/api/nullwatch/v1/runs"));
    try std.testing.expect(isProxyPath("/api/nullwatch/health"));
    try std.testing.expect(!isProxyPath("/api/nullboiler/v1/runs"));
    try std.testing.expect(!isProxyPath("/api/nulltickets/store/runs"));
}

test "handle returns not configured without NullWatch URL" {
    const resp = handle(std.testing.allocator, "GET", "/api/nullwatch/v1/summary", "", .{});
    try std.testing.expectEqualStrings("503 Service Unavailable", resp.status);
    try std.testing.expectEqualStrings("{\"error\":\"NullWatch not configured\"}", resp.body);
}

test "handle rejects non-NullWatch paths" {
    const resp = handle(std.testing.allocator, "GET", "/api/status", "", .{
        .watch_url = "http://127.0.0.1:7710",
    });
    try std.testing.expectEqualStrings("404 Not Found", resp.status);
}

test "selectedWatchNameAlloc reads hub selector query params" {
    const allocator = std.testing.allocator;
    const selected = (try selectedWatchNameAlloc(allocator, "/api/nullwatch/v1/runs?limit=1&nullhub_watch=watch+one")).?;
    defer allocator.free(selected);
    try std.testing.expectEqualStrings("watch one", selected);
    try std.testing.expect((try selectedWatchNameAlloc(allocator, "/api/nullwatch/v1/runs?watch=upstream")) == null);
}

test "rewriteProductProxyTarget removes only NullHub watch selector" {
    const allocator = std.testing.allocator;
    const selector_params = [_][]const u8{"nullhub_watch"};
    var stripped = try http_proxy.rewriteProductProxyTarget(allocator, "/api/nullwatch/v1/runs?limit=50&nullhub_watch=alpha&status=ok", .{
        .prefix = prefix,
        .selector_params = selector_params[0..],
        .default_path = "/v1/summary",
    });
    defer stripped.deinit(allocator);
    try std.testing.expectEqualStrings("/api/nullwatch/v1/runs?limit=50&status=ok", stripped.target);
    try std.testing.expectEqualStrings("/v1/runs?limit=50&status=ok", stripped.path);

    var root = try http_proxy.rewriteProductProxyTarget(allocator, "/api/nullwatch?nullhub_watch=alpha", .{
        .prefix = prefix,
        .selector_params = selector_params[0..],
        .default_path = "/v1/summary",
    });
    defer root.deinit(allocator);
    try std.testing.expectEqualStrings("/api/nullwatch", root.target);
    try std.testing.expectEqualStrings("/v1/summary", root.path);

    var upstream_filter = try http_proxy.rewriteProductProxyTarget(allocator, "/api/nullwatch/v1/runs?watch=alpha&instance=demo", .{
        .prefix = prefix,
        .selector_params = selector_params[0..],
        .default_path = "/v1/summary",
    });
    defer upstream_filter.deinit(allocator);
    try std.testing.expectEqualStrings("/api/nullwatch/v1/runs?watch=alpha&instance=demo", upstream_filter.target);
    try std.testing.expectEqualStrings("/v1/runs?watch=alpha&instance=demo", upstream_filter.path);
}

test "handle forwards NullWatch path, strips selector, and sends bearer token" {
    if (comptime @import("builtin").os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var upstream = try http_proxy.TestUpstream.start(allocator, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 11\r\n\r\n{\"ok\":true}");
    defer upstream.deinit();

    const base_url = try upstream.baseUrl(allocator);
    defer allocator.free(base_url);

    const resp = handle(allocator, "GET", "/api/nullwatch/v1/runs?limit=50&nullhub_watch=alpha&status=ok", "", .{
        .watch_url = base_url,
        .watch_token = "watch-token",
    });
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expectEqualStrings("{\"ok\":true}", resp.body);
    try std.testing.expect(std.mem.indexOf(u8, upstream.request(), "GET /v1/runs?limit=50&status=ok HTTP/1.1") != null);
    try std.testing.expect(std.mem.indexOf(u8, upstream.request(), "Authorization: Bearer watch-token") != null);
    try std.testing.expect(std.mem.indexOf(u8, upstream.request(), "nullhub_watch") == null);
}
