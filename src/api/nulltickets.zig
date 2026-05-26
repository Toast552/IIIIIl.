const std = @import("std");
const http_proxy = @import("proxy.zig");
const query_api = @import("query.zig");

const Allocator = std.mem.Allocator;
const Response = http_proxy.Response;

const prefix = "/api/nulltickets";
const store_prefix = "/api/nulltickets/store";

pub const Config = struct {
    tickets_url: ?[]const u8 = null,
    tickets_token: ?[]const u8 = null,
};

pub fn isProxyPath(target: []const u8) bool {
    const clean = query_api.stripTarget(target);
    return std.mem.eql(u8, clean, store_prefix) or std.mem.startsWith(u8, clean, store_prefix ++ "/");
}

pub fn requestedTicketsInstance(allocator: Allocator, target: []const u8) !?[]u8 {
    if (!isProxyPath(target)) return null;
    const value = (try query_api.valueAlloc(allocator, target, "tickets_instance")) orelse return null;
    if (value.len == 0) {
        allocator.free(value);
        return null;
    }
    return value;
}

/// Proxies NullTickets store API requests. The `/api/nulltickets` prefix is
/// stripped before forwarding, so `/api/nulltickets/store/ns` becomes `/store/ns`.
pub fn handle(allocator: Allocator, method: []const u8, target: []const u8, body: []const u8, cfg: Config) Response {
    if (!isProxyPath(target)) {
        return .{ .status = "404 Not Found", .content_type = "application/json", .body = "{\"error\":\"not found\"}" };
    }

    const base_url = cfg.tickets_url orelse
        return .{ .status = "503 Service Unavailable", .content_type = "application/json", .body = "{\"error\":\"NullTickets not configured\"}" };

    const selector_params = [_][]const u8{"tickets_instance"};
    var forwarded = http_proxy.rewriteProductProxyTarget(allocator, target, .{
        .prefix = prefix,
        .selector_params = selector_params[0..],
        .default_path = "/",
    }) catch
        return .{ .status = "500 Internal Server Error", .content_type = "application/json", .body = "{\"error\":\"internal error\"}" };
    defer forwarded.deinit(allocator);

    return http_proxy.forward(allocator, .{
        .method = method,
        .base_url = base_url,
        .path = forwarded.path,
        .body = body,
        .bearer_token = cfg.tickets_token,
        .unreachable_body = "{\"error\":\"NullTickets unreachable\"}",
    });
}

test "isProxyPath matches NullTickets store namespace" {
    try std.testing.expect(isProxyPath("/api/nulltickets/store"));
    try std.testing.expect(isProxyPath("/api/nulltickets/store?tickets_instance=tracker-a"));
    try std.testing.expect(isProxyPath("/api/nulltickets/store/search"));
    try std.testing.expect(!isProxyPath("/api/nulltickets"));
    try std.testing.expect(!isProxyPath("/api/nullboiler/runs"));
    try std.testing.expect(!isProxyPath("/api/nulltickets/tasks"));
}

test "requestedTicketsInstance decodes store target selection" {
    const allocator = std.testing.allocator;
    const value = (try requestedTicketsInstance(allocator, "/api/nulltickets/store/ns?tickets_instance=tracker%20a")).?;
    defer allocator.free(value);
    try std.testing.expectEqualStrings("tracker a", value);
    try std.testing.expect(try requestedTicketsInstance(allocator, "/api/nullboiler/runs?tickets_instance=tracker-a") == null);
}

test "rewriteProductProxyTarget strips only NullTickets selector params" {
    const allocator = std.testing.allocator;
    const selector_params = [_][]const u8{"tickets_instance"};
    var forwarded = try http_proxy.rewriteProductProxyTarget(allocator, "/api/nulltickets/store/search?q=tasks&tickets_instance=tracker-a&limit=10", .{
        .prefix = prefix,
        .selector_params = selector_params[0..],
    });
    defer forwarded.deinit(allocator);
    try std.testing.expectEqualStrings("/api/nulltickets/store/search?q=tasks&limit=10", forwarded.target);
    try std.testing.expectEqualStrings("/store/search?q=tasks&limit=10", forwarded.path);

    var upstream_filter = try http_proxy.rewriteProductProxyTarget(allocator, "/api/nulltickets/store/search?owner=team-a", .{
        .prefix = prefix,
        .selector_params = selector_params[0..],
    });
    defer upstream_filter.deinit(allocator);
    try std.testing.expectEqualStrings("/api/nulltickets/store/search?owner=team-a", upstream_filter.target);
    try std.testing.expectEqualStrings("/store/search?owner=team-a", upstream_filter.path);
}

test "handle returns not configured without NullTickets URL" {
    const resp = handle(std.testing.allocator, "GET", "/api/nulltickets/store/search", "", .{});
    try std.testing.expectEqualStrings("503 Service Unavailable", resp.status);
    try std.testing.expectEqualStrings("{\"error\":\"NullTickets not configured\"}", resp.body);
}

test "handle returns 404 for non-store NullTickets paths" {
    const resp = handle(std.testing.allocator, "GET", "/api/nulltickets/tasks", "", .{
        .tickets_url = "http://127.0.0.1:7711",
    });
    try std.testing.expectEqualStrings("404 Not Found", resp.status);
    try std.testing.expectEqualStrings("{\"error\":\"not found\"}", resp.body);
}

test "handle rejects unsupported methods before fetch" {
    const resp = handle(std.testing.allocator, "HEAD", "/api/nulltickets/store/search", "", .{
        .tickets_url = "http://127.0.0.1:7711",
    });
    try std.testing.expectEqualStrings("405 Method Not Allowed", resp.status);
    try std.testing.expectEqualStrings("{\"error\":\"method not allowed\"}", resp.body);
}

test "handle forwards store path, strips selector, and sends bearer token" {
    if (comptime @import("builtin").os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var upstream = try http_proxy.TestUpstream.start(allocator, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 11\r\n\r\n{\"ok\":true}");
    defer upstream.deinit();

    const base_url = try upstream.baseUrl(allocator);
    defer allocator.free(base_url);

    const resp = handle(allocator, "GET", "/api/nulltickets/store/search?q=tasks&tickets_instance=tracker-a&limit=10", "", .{
        .tickets_url = base_url,
        .tickets_token = "tickets-token",
    });
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("200 OK", resp.status);
    try std.testing.expectEqualStrings("{\"ok\":true}", resp.body);
    try std.testing.expect(std.mem.indexOf(u8, upstream.request(), "GET /store/search?q=tasks&limit=10 HTTP/1.1") != null);
    try std.testing.expect(std.mem.indexOf(u8, upstream.request(), "Authorization: Bearer tickets-token") != null);
    try std.testing.expect(std.mem.indexOf(u8, upstream.request(), "tickets_instance") == null);
}
