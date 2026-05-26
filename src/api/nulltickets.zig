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

    var forwarded = forwardedTarget(allocator, target) catch
        return .{ .status = "500 Internal Server Error", .content_type = "application/json", .body = "{\"error\":\"internal error\"}" };
    defer forwarded.deinit(allocator);

    const proxied_path = forwarded.value[prefix.len..];
    const path = if (proxied_path.len == 0) "/" else proxied_path;

    return http_proxy.forward(allocator, .{
        .method = method,
        .base_url = base_url,
        .path = path,
        .body = body,
        .bearer_token = cfg.tickets_token,
        .unreachable_body = "{\"error\":\"NullTickets unreachable\"}",
    });
}

const ForwardedTarget = struct {
    value: []const u8,
    owned: bool = false,

    fn deinit(self: *ForwardedTarget, allocator: Allocator) void {
        if (self.owned) allocator.free(self.value);
        self.* = .{ .value = "" };
    }
};

fn forwardedTarget(allocator: Allocator, target: []const u8) !ForwardedTarget {
    const qmark = std.mem.indexOfScalar(u8, target, '?') orelse return .{ .value = target };
    var stripped_any = false;
    var buf = std.array_list.Managed(u8).init(allocator);
    errdefer buf.deinit();

    try buf.appendSlice(target[0..qmark]);
    var wrote_query = false;
    var params = std.mem.splitScalar(u8, target[qmark + 1 ..], '&');
    while (params.next()) |param| {
        if (isHubProxyParam(param)) {
            stripped_any = true;
            continue;
        }
        try buf.append(if (wrote_query) '&' else '?');
        wrote_query = true;
        try buf.appendSlice(param);
    }

    if (!stripped_any) {
        buf.deinit();
        return .{ .value = target };
    }
    return .{ .value = try buf.toOwnedSlice(), .owned = true };
}

fn isHubProxyParam(param: []const u8) bool {
    const key = if (std.mem.indexOfScalar(u8, param, '=')) |eq| param[0..eq] else param;
    return std.mem.eql(u8, key, "tickets_instance");
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

test "forwardedTarget strips only NullTickets selector params" {
    const allocator = std.testing.allocator;
    var forwarded = try forwardedTarget(allocator, "/api/nulltickets/store/search?q=tasks&tickets_instance=tracker-a&limit=10");
    defer forwarded.deinit(allocator);
    try std.testing.expectEqualStrings("/api/nulltickets/store/search?q=tasks&limit=10", forwarded.value);

    var upstream_filter = try forwardedTarget(allocator, "/api/nulltickets/store/search?owner=team-a");
    defer upstream_filter.deinit(allocator);
    try std.testing.expectEqualStrings("/api/nulltickets/store/search?owner=team-a", upstream_filter.value);
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
