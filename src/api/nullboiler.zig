const std = @import("std");
const http_proxy = @import("proxy.zig");
const query_api = @import("query.zig");

const Allocator = std.mem.Allocator;
const Response = http_proxy.Response;

const prefix = "/api/nullboiler";

pub const Config = struct {
    boiler_url: ?[]const u8 = null,
    boiler_token: ?[]const u8 = null,
};

pub fn isProxyPath(target: []const u8) bool {
    return http_proxy.isTargetInNamespace(target, prefix);
}

pub fn requestedBoilerInstance(allocator: Allocator, target: []const u8) !?[]u8 {
    if (!isProxyPath(target)) return null;
    const value = (try query_api.valueAlloc(allocator, target, "boiler_instance")) orelse return null;
    if (value.len == 0) {
        allocator.free(value);
        return null;
    }
    return value;
}

/// Proxies NullBoiler API requests. The shared `/api/nullboiler` prefix is
/// stripped before forwarding, so `/api/nullboiler/runs` becomes `/runs`.
pub fn handle(allocator: Allocator, method: []const u8, target: []const u8, body: []const u8, cfg: Config) Response {
    if (!isProxyPath(target)) {
        return .{ .status = "404 Not Found", .content_type = "application/json", .body = "{\"error\":\"not found\"}" };
    }

    const base_url = cfg.boiler_url orelse
        return .{ .status = "503 Service Unavailable", .content_type = "application/json", .body = "{\"error\":\"NullBoiler not configured\"}" };

    const selector_params = [_][]const u8{"boiler_instance"};
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
        .bearer_token = cfg.boiler_token,
        .unreachable_body = "{\"error\":\"NullBoiler unreachable\"}",
    });
}

test "isProxyPath matches NullBoiler namespace" {
    try std.testing.expect(isProxyPath("/api/nullboiler"));
    try std.testing.expect(isProxyPath("/api/nullboiler?boiler_instance=worker-a"));
    try std.testing.expect(isProxyPath("/api/nullboiler/runs"));
    try std.testing.expect(!isProxyPath("/api/nulltickets/store/search"));
    try std.testing.expect(!isProxyPath("/api/nullwatch/v1/runs"));
    try std.testing.expect(!isProxyPath("/api/instances"));
}

test "requestedBoilerInstance decodes NullBoiler target selection" {
    const allocator = std.testing.allocator;
    const value = (try requestedBoilerInstance(allocator, "/api/nullboiler/workflows?boiler_instance=boiler%20a")).?;
    defer allocator.free(value);
    try std.testing.expectEqualStrings("boiler a", value);
    try std.testing.expect(try requestedBoilerInstance(allocator, "/api/nulltickets/store/ns?boiler_instance=boiler-a") == null);
}

test "rewriteProductProxyTarget strips only NullBoiler selector params" {
    const allocator = std.testing.allocator;
    const selector_params = [_][]const u8{"boiler_instance"};
    var forwarded = try http_proxy.rewriteProductProxyTarget(allocator, "/api/nullboiler/runs?boiler_instance=boiler-a&status=running", .{
        .prefix = prefix,
        .selector_params = selector_params[0..],
    });
    defer forwarded.deinit(allocator);
    try std.testing.expectEqualStrings("/api/nullboiler/runs?status=running", forwarded.target);
    try std.testing.expectEqualStrings("/runs?status=running", forwarded.path);

    var upstream_filter = try http_proxy.rewriteProductProxyTarget(allocator, "/api/nullboiler/runs?worker=primary", .{
        .prefix = prefix,
        .selector_params = selector_params[0..],
    });
    defer upstream_filter.deinit(allocator);
    try std.testing.expectEqualStrings("/api/nullboiler/runs?worker=primary", upstream_filter.target);
    try std.testing.expectEqualStrings("/runs?worker=primary", upstream_filter.path);
}

test "handle returns not configured without NullBoiler URL" {
    const resp = handle(std.testing.allocator, "GET", "/api/nullboiler/runs", "", .{});
    try std.testing.expectEqualStrings("503 Service Unavailable", resp.status);
    try std.testing.expectEqualStrings("{\"error\":\"NullBoiler not configured\"}", resp.body);
}

test "handle returns 404 for non-NullBoiler paths" {
    const resp = handle(std.testing.allocator, "GET", "/api/status", "", .{});
    try std.testing.expectEqualStrings("404 Not Found", resp.status);
    try std.testing.expectEqualStrings("{\"error\":\"not found\"}", resp.body);
}

test "handle rejects unsupported methods before fetch" {
    const resp = handle(std.testing.allocator, "HEAD", "/api/nullboiler/runs", "", .{
        .boiler_url = "http://127.0.0.1:8080",
    });
    try std.testing.expectEqualStrings("405 Method Not Allowed", resp.status);
    try std.testing.expectEqualStrings("{\"error\":\"method not allowed\"}", resp.body);
}

test "handle passes through upstream 409 status and body" {
    if (comptime @import("builtin").os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var upstream = try http_proxy.TestUpstream.start(allocator, "HTTP/1.1 409 Conflict\r\nContent-Type: application/json\r\nContent-Length: 20\r\n\r\n{\"error\":\"conflict\"}");
    defer upstream.deinit();

    const base_url = try upstream.baseUrl(allocator);
    defer allocator.free(base_url);

    const resp = handle(allocator, "GET", "/api/nullboiler/runs?boiler_instance=boiler-a&status=running", "", .{
        .boiler_url = base_url,
        .boiler_token = "boiler-token",
    });
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("409 Conflict", resp.status);
    try std.testing.expectEqualStrings("{\"error\":\"conflict\"}", resp.body);
    try std.testing.expect(std.mem.indexOf(u8, upstream.request(), "GET /runs?status=running HTTP/1.1") != null);
    try std.testing.expect(std.mem.indexOf(u8, upstream.request(), "Authorization: Bearer boiler-token") != null);
    try std.testing.expect(std.mem.indexOf(u8, upstream.request(), "boiler_instance") == null);
}
