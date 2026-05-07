const std = @import("std");
const std_compat = @import("compat");
const http_proxy = @import("proxy.zig");
const Allocator = std.mem.Allocator;
const query_api = @import("query.zig");

const Response = http_proxy.Response;

const prefix = "/api/orchestration";
const store_prefix = "/api/orchestration/store";

pub const Config = struct {
    boiler_url: ?[]const u8 = null,
    boiler_token: ?[]const u8 = null,
    tickets_url: ?[]const u8 = null,
    tickets_token: ?[]const u8 = null,
};

const Backend = enum {
    boiler,
    tickets,

    fn notConfiguredBody(self: Backend) []const u8 {
        return switch (self) {
            .boiler => "{\"error\":\"NullBoiler not configured\"}",
            .tickets => "{\"error\":\"NullTickets not configured\"}",
        };
    }

    fn unreachableBody(self: Backend) []const u8 {
        return switch (self) {
            .boiler => "{\"error\":\"NullBoiler unreachable\"}",
            .tickets => "{\"error\":\"NullTickets unreachable\"}",
        };
    }
};

pub fn isProxyPath(target: []const u8) bool {
    const clean = query_api.stripTarget(target);
    return http_proxy.isPathInNamespace(clean, prefix);
}

fn isStorePath(target: []const u8) bool {
    const clean = query_api.stripTarget(target);
    return std.mem.eql(u8, clean, store_prefix) or std.mem.startsWith(u8, clean, store_prefix ++ "/");
}

const ProxyTarget = struct {
    backend: Backend,
    base_url: []const u8,
    token: ?[]const u8,
};

fn backendForPath(target: []const u8) ?Backend {
    if (!isProxyPath(target)) return null;
    return if (isStorePath(target)) .tickets else .boiler;
}

pub fn requestedTicketsInstance(allocator: Allocator, target: []const u8) !?[]u8 {
    if (!isStorePath(target)) return null;
    const value = (try query_api.valueAlloc(allocator, target, "tickets_instance")) orelse return null;
    if (value.len == 0) {
        allocator.free(value);
        return null;
    }
    return value;
}

pub fn requestedBoilerInstance(allocator: Allocator, target: []const u8) !?[]u8 {
    if (!isProxyPath(target) or isStorePath(target)) return null;
    const value = (try query_api.valueAlloc(allocator, target, "boiler_instance")) orelse return null;
    if (value.len == 0) {
        allocator.free(value);
        return null;
    }
    return value;
}

fn resolveProxyTarget(target: []const u8, cfg: Config) ?ProxyTarget {
    const backend = backendForPath(target) orelse return null;
    return switch (backend) {
        .tickets => blk: {
            const base_url = cfg.tickets_url orelse return null;
            break :blk .{
                .backend = .tickets,
                .base_url = base_url,
                .token = cfg.tickets_token,
            };
        },
        .boiler => blk: {
            const base_url = cfg.boiler_url orelse return null;
            break :blk .{
                .backend = .boiler,
                .base_url = base_url,
                .token = cfg.boiler_token,
            };
        },
    };
}

/// Proxies orchestration API requests to the local orchestration stack.
/// `/api/orchestration/store/*` goes to NullTickets; all other orchestration
/// routes go to NullBoiler. The shared prefix is stripped before forwarding.
pub fn handle(allocator: Allocator, method: []const u8, target: []const u8, body: []const u8, cfg: Config) Response {
    if (!isProxyPath(target)) {
        return .{ .status = "404 Not Found", .content_type = "application/json", .body = "{\"error\":\"not found\"}" };
    }
    const backend = backendForPath(target) orelse
        return .{ .status = "404 Not Found", .content_type = "application/json", .body = "{\"error\":\"not found\"}" };
    const resolved = resolveProxyTarget(target, cfg) orelse
        return .{ .status = "503 Service Unavailable", .content_type = "application/json", .body = backend.notConfiguredBody() };

    var forwarded = forwardedTarget(allocator, target) catch
        return .{ .status = "500 Internal Server Error", .content_type = "application/json", .body = "{\"error\":\"internal error\"}" };
    defer forwarded.deinit(allocator);

    const proxied_path = forwarded.value[prefix.len..];
    const path = if (proxied_path.len == 0) "/" else proxied_path;

    return http_proxy.forward(allocator, .{
        .method = method,
        .base_url = resolved.base_url,
        .path = path,
        .body = body,
        .bearer_token = resolved.token,
        .unreachable_body = resolved.backend.unreachableBody(),
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
    return std.mem.eql(u8, key, "tickets_instance") or std.mem.eql(u8, key, "boiler_instance");
}

const TestUpstream = struct {
    allocator: Allocator,
    ctx: *Context,
    thread: std.Thread,

    const Context = struct {
        server: std_compat.net.Server,
        stop_flag: std.atomic.Value(bool),
        response: []u8,

        fn run(ctx: *Context) void {
            while (!ctx.stop_flag.load(.acquire)) {
                var conn = ctx.server.accept() catch |err| switch (err) {
                    error.WouldBlock => {
                        std_compat.thread.sleep(10 * std.time.ns_per_ms);
                        continue;
                    },
                    else => return,
                };
                defer conn.stream.close();

                var read_buf: [1024]u8 = undefined;
                _ = conn.stream.read(&read_buf) catch return;
                _ = conn.stream.write(ctx.response) catch return;
                return;
            }
        }
    };

    fn start(allocator: Allocator, response: []const u8) !TestUpstream {
        const response_owned = try allocator.dupe(u8, response);
        errdefer allocator.free(response_owned);

        const ctx = try allocator.create(Context);
        errdefer allocator.destroy(ctx);
        ctx.* = .{
            .server = undefined,
            .stop_flag = std.atomic.Value(bool).init(false),
            .response = response_owned,
        };

        const addr = try std_compat.net.Address.resolveIp("127.0.0.1", 0);
        ctx.server = try addr.listen(.{});
        errdefer ctx.server.deinit();

        const thread = try std.Thread.spawn(.{}, Context.run, .{ctx});

        return .{
            .allocator = allocator,
            .ctx = ctx,
            .thread = thread,
        };
    }

    fn deinit(self: *TestUpstream) void {
        self.ctx.stop_flag.store(true, .release);
        self.thread.join();
        self.ctx.server.deinit();
        self.allocator.free(self.ctx.response);
        self.allocator.destroy(self.ctx);
    }

    fn baseUrl(self: *const TestUpstream, allocator: Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{self.ctx.server.listen_address.in.getPort()});
    }
};

test "isProxyPath matches orchestration namespace" {
    try std.testing.expect(isProxyPath("/api/orchestration"));
    try std.testing.expect(isProxyPath("/api/orchestration?tickets_instance=tracker-a"));
    try std.testing.expect(isProxyPath("/api/orchestration/runs"));
    try std.testing.expect(isProxyPath("/api/orchestration/store/search"));
    try std.testing.expect(!isProxyPath("/api/instances"));
}

test "backendForPath routes store requests to tickets backend" {
    try std.testing.expectEqual(Backend.tickets, backendForPath("/api/orchestration/store/search?tickets_instance=tracker-a").?);
    try std.testing.expectEqual(Backend.boiler, backendForPath("/api/orchestration/runs").?);
}

test "requestedTicketsInstance decodes store target selection" {
    const allocator = std.testing.allocator;
    const value = (try requestedTicketsInstance(allocator, "/api/orchestration/store/ns?tickets_instance=tracker%20a")).?;
    defer allocator.free(value);
    try std.testing.expectEqualStrings("tracker a", value);
    try std.testing.expect(try requestedTicketsInstance(allocator, "/api/orchestration/runs?tickets_instance=tracker-a") == null);
}

test "requestedBoilerInstance decodes orchestration target selection" {
    const allocator = std.testing.allocator;
    const value = (try requestedBoilerInstance(allocator, "/api/orchestration/workflows?boiler_instance=boiler%20a")).?;
    defer allocator.free(value);
    try std.testing.expectEqualStrings("boiler a", value);
    try std.testing.expect(try requestedBoilerInstance(allocator, "/api/orchestration/store/ns?boiler_instance=boiler-a") == null);
}

test "forwardedTarget strips hub-only proxy params" {
    const allocator = std.testing.allocator;
    var forwarded = try forwardedTarget(allocator, "/api/orchestration/store/search?q=tasks&tickets_instance=tracker-a&limit=10");
    defer forwarded.deinit(allocator);
    try std.testing.expectEqualStrings("/api/orchestration/store/search?q=tasks&limit=10", forwarded.value);

    var boiler_forwarded = try forwardedTarget(allocator, "/api/orchestration/runs?boiler_instance=boiler-a&status=running");
    defer boiler_forwarded.deinit(allocator);
    try std.testing.expectEqualStrings("/api/orchestration/runs?status=running", boiler_forwarded.value);
}

test "handle routes store paths to NullTickets config" {
    const resp = handle(std.testing.allocator, "GET", "/api/orchestration/store/search", "", .{
        .boiler_url = "http://127.0.0.1:8080",
    });
    try std.testing.expectEqualStrings("503 Service Unavailable", resp.status);
    try std.testing.expectEqualStrings("{\"error\":\"NullTickets not configured\"}", resp.body);
}

test "handle routes non-store paths to NullBoiler config" {
    const resp = handle(std.testing.allocator, "GET", "/api/orchestration/runs", "", .{
        .tickets_url = "http://127.0.0.1:7711",
    });
    try std.testing.expectEqualStrings("503 Service Unavailable", resp.status);
    try std.testing.expectEqualStrings("{\"error\":\"NullBoiler not configured\"}", resp.body);
}

test "handle returns 404 for non-orchestration paths" {
    const resp = handle(std.testing.allocator, "GET", "/api/status", "", .{});
    try std.testing.expectEqualStrings("404 Not Found", resp.status);
    try std.testing.expectEqualStrings("{\"error\":\"not found\"}", resp.body);
}

test "handle rejects unsupported methods before fetch" {
    const resp = handle(std.testing.allocator, "HEAD", "/api/orchestration/runs", "", .{
        .boiler_url = "http://127.0.0.1:8080",
    });
    try std.testing.expectEqualStrings("405 Method Not Allowed", resp.status);
    try std.testing.expectEqualStrings("{\"error\":\"method not allowed\"}", resp.body);
}

test "handle passes through upstream 409 status and body" {
    if (comptime @import("builtin").os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var upstream = try TestUpstream.start(allocator, "HTTP/1.1 409 Conflict\r\nContent-Type: application/json\r\nContent-Length: 20\r\n\r\n{\"error\":\"conflict\"}");
    defer upstream.deinit();

    const base_url = try upstream.baseUrl(allocator);
    defer allocator.free(base_url);

    const resp = handle(allocator, "GET", "/api/orchestration/runs", "", .{
        .boiler_url = base_url,
    });
    defer allocator.free(resp.body);

    try std.testing.expectEqualStrings("409 Conflict", resp.status);
    try std.testing.expectEqualStrings("{\"error\":\"conflict\"}", resp.body);
}
