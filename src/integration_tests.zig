const std = @import("std");
const std_compat = @import("compat");
const builtin = @import("builtin");

const IntegrationServer = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    temp_root: []const u8,
    home_dir: []const u8,
    port: u16,
    child: ?std_compat.process.Child = null,
    env_map: ?std_compat.process.EnvMap = null,

    fn start(allocator: std.mem.Allocator) !IntegrationServer {
        if (builtin.os.tag == .wasi) return error.SkipZigTest;

        return startWithSeed(allocator, struct {
            fn call(_: *IntegrationServer) !void {}
        }.call);
    }

    fn startWithSeed(
        allocator: std.mem.Allocator,
        comptime seedFn: *const fn (*IntegrationServer) anyerror!void,
    ) !IntegrationServer {
        if (builtin.os.tag == .wasi) return error.SkipZigTest;

        var tmp_dir = std.testing.tmpDir(.{});
        var cleanup_tmp_dir = true;
        errdefer if (cleanup_tmp_dir) tmp_dir.cleanup();

        const temp_root = try std_compat.fs.Dir.wrap(tmp_dir.dir).realpathAlloc(allocator, ".");
        var cleanup_temp_root = true;
        errdefer if (cleanup_temp_root) allocator.free(temp_root);

        const home_dir = try std.fs.path.join(allocator, &.{ temp_root, "home" });
        var cleanup_home_dir = true;
        errdefer if (cleanup_home_dir) allocator.free(home_dir);
        try std_compat.fs.makeDirAbsolute(home_dir);

        var server = IntegrationServer{
            .allocator = allocator,
            .tmp_dir = tmp_dir,
            .temp_root = temp_root,
            .home_dir = home_dir,
            .port = undefined,
        };
        cleanup_tmp_dir = false;
        cleanup_temp_root = false;
        cleanup_home_dir = false;
        errdefer server.deinit();

        try seedFn(&server);

        const port = try reservePort();
        server.port = port;
        const port_text = try std.fmt.allocPrint(allocator, "{d}", .{port});
        defer allocator.free(port_text);

        const exe_path = try std_compat.process.getEnvVarOwned(allocator, "NULLHUB_INTEGRATION_BIN");
        defer allocator.free(exe_path);

        server.env_map = try std_compat.process.getEnvMap(allocator);
        try server.env_map.?.put("HOME", home_dir);

        const argv = try allocator.dupe([]const u8, &.{ exe_path, "serve", "--port", port_text, "--no-open" });
        defer allocator.free(argv);

        var child = std_compat.process.Child.init(argv, allocator);
        child.cwd = ".";
        child.env_map = &server.env_map.?;
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = if (builtin.os.tag == .windows) .Inherit else .Ignore;
        try child.spawn();
        child.argv = &.{};
        server.child = child;

        try server.waitUntilReady();
        return server;
    }

    fn deinit(self: *IntegrationServer) void {
        if (self.child) |*child| {
            _ = child.kill() catch {};
            _ = child.wait() catch {};
        }
        if (self.env_map) |*env_map| env_map.deinit();
        self.allocator.free(self.home_dir);
        self.allocator.free(self.temp_root);
        self.tmp_dir.cleanup();
        self.* = undefined;
    }

    fn waitUntilReady(self: *IntegrationServer) !void {
        var attempt: usize = 0;
        const max_attempts = 40;
        while (attempt < max_attempts) : (attempt += 1) {
            const result = self.fetch(.{ .path = "/health" });
            if (result) |resp| {
                defer resp.deinit(self.allocator);
                if (resp.status == .ok) return;
            } else |_| {}

            std_compat.thread.sleep(250 * std.time.ns_per_ms);
        }

        return error.ServerNotReady;
    }

    fn fetch(self: *IntegrationServer, req: Request) !HttpResponse {
        const url = try std.fmt.allocPrint(self.allocator, "http://127.0.0.1:{d}{s}", .{ self.port, req.path });
        defer self.allocator.free(url);

        const payload = payloadForRequest(req.method, req.body);
        var headers: std.http.Client.Request.Headers = .{
            .connection = .{ .override = "close" },
        };
        if (payload) |bytes| {
            if (bytes.len > 0) {
                headers.content_type = .{ .override = "application/json" };
            }
        }

        var client: std.http.Client = .{
            .allocator = self.allocator,
            .io = std_compat.io(),
        };
        defer client.deinit();

        var body: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer body.deinit();

        const result = try client.fetch(.{
            .location = .{ .url = url },
            .method = req.method,
            .payload = payload,
            .keep_alive = false,
            .headers = headers,
            .response_writer = &body.writer,
        });

        return .{
            .status = result.status,
            .body = try body.toOwnedSlice(),
        };
    }

    fn nullhubRoot(self: *IntegrationServer) ![]const u8 {
        return std.fs.path.join(self.allocator, &.{ self.home_dir, ".nullhub" });
    }
};

fn payloadForRequest(method: std.http.Method, body: []const u8) ?[]const u8 {
    if (body.len > 0) return body;
    if (method.requestHasBody()) return body;
    return null;
}

const Request = struct {
    path: []const u8,
    method: std.http.Method = .GET,
    body: []const u8 = "",
};

const HttpResponse = struct {
    status: std.http.Status,
    body: []u8,

    fn deinit(self: HttpResponse, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
    }
};

fn reservePort() !u16 {
    const addr = try std_compat.net.Address.resolveIp("127.0.0.1", 0);
    var listener = try addr.listen(.{});
    defer listener.deinit();
    return listener.listen_address.in.getPort();
}

const StateInstanceEntry = struct {
    version: []const u8,
    auto_start: bool = false,
    launch_mode: []const u8 = "gateway",
    verbose: bool = false,
};

fn seedManagedInstance(server: *IntegrationServer, component: []const u8, name: []const u8) !void {
    const root = try server.nullhubRoot();
    defer server.allocator.free(root);
    try std_compat.fs.cwd().makePath(root);

    const state_path = try std.fs.path.join(server.allocator, &.{ root, "state.json" });
    defer server.allocator.free(state_path);

    var component_instances = std.json.ArrayHashMap(StateInstanceEntry){};
    defer component_instances.deinit(server.allocator);
    try component_instances.map.put(server.allocator, name, .{
        .version = "1.0.0",
        .auto_start = false,
        .launch_mode = "gateway",
        .verbose = false,
    });

    var instances = std.json.ArrayHashMap(std.json.ArrayHashMap(StateInstanceEntry)){};
    defer instances.deinit(server.allocator);
    try instances.map.put(server.allocator, component, component_instances);

    const state_json = try std.json.Stringify.valueAlloc(server.allocator, .{
        .instances = instances,
        .saved_providers = &.{},
        .saved_channels = &.{},
    }, .{ .whitespace = .indent_2 });
    defer server.allocator.free(state_json);

    const file = try std_compat.fs.createFileAbsolute(state_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(state_json);
}

fn writeSeedFile(server: *IntegrationServer, parts: []const []const u8, contents: []const u8) !void {
    const path = try std.fs.path.join(server.allocator, parts);
    defer server.allocator.free(path);

    if (parts.len < 2) return error.InvalidPath;
    var root_dir = try std_compat.fs.openDirAbsolute(parts[0], .{});
    defer root_dir.close();

    if (parts.len > 2) {
        const parent_rel = try std.fs.path.join(server.allocator, parts[1 .. parts.len - 1]);
        defer server.allocator.free(parent_rel);
        try root_dir.makePath(parent_rel);
    }

    const file = try std_compat.fs.createFileAbsolute(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(contents);
}

fn seedLaunchableGatewayInstance(server: *IntegrationServer, component: []const u8, name: []const u8, port: u16) !void {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    try seedManagedInstance(server, component, name);

    const root = try server.nullhubRoot();
    defer server.allocator.free(root);

    const config_json = try std.fmt.allocPrint(server.allocator, "{{\"gateway\":{{\"port\":{d}}}}}", .{port});
    defer server.allocator.free(config_json);
    try writeSeedFile(server, &.{ root, "instances", component, name, "config.json" }, config_json);

    const binary_name = try std.fmt.allocPrint(server.allocator, "{s}-{s}", .{ component, "1.0.0" });
    defer server.allocator.free(binary_name);
    const script =
        \\#!/bin/sh
        \\set -eu
        \\if [ "${1:-}" = "--export-manifest" ]; then
        \\  printf '%s\n' '{"schema_version":1,"name":"nullboiler","display_name":"NullBoiler","description":"test fixture","icon":"boiler","repo":"nullclaw/nullboiler","platforms":{},"launch":{"command":"gateway","args":[]},"health":{"endpoint":"/health","port_from_config":"gateway.port","interval_ms":15000},"ports":[{"name":"gateway","config_key":"gateway.port","default":3000,"protocol":"http"}],"wizard":{"steps":[]},"depends_on":[],"connects_to":[]}'
        \\  exit 0
        \\fi
        \\if [ "${1:-}" = "gateway" ]; then
        \\  exec python3 -c 'import signal,sys,time; signal.signal(signal.SIGTERM, lambda *_: sys.exit(0)); signal.signal(signal.SIGINT, lambda *_: sys.exit(0)); time.sleep(60)'
        \\fi
        \\exit 64
    ;
    try writeSeedFile(server, &.{ root, "bin", binary_name }, script);

    const binary_path = try std.fs.path.join(server.allocator, &.{ root, "bin", binary_name });
    defer server.allocator.free(binary_path);
    if (comptime std_compat.fs.has_executable_bit) {
        const file = try std_compat.fs.openFileAbsolute(binary_path, .{});
        defer file.close();
        try file.chmod(0o755);
    }
}

test "integration harness serves health and core api routes" {
    var server = try IntegrationServer.start(std.testing.allocator);
    defer server.deinit();

    {
        const resp = try server.fetch(.{ .path = "/health" });
        defer resp.deinit(std.testing.allocator);
        try std.testing.expectEqual(std.http.Status.ok, resp.status);
    }

    {
        const resp = try server.fetch(.{ .path = "/api/status" });
        defer resp.deinit(std.testing.allocator);
        try std.testing.expectEqual(std.http.Status.ok, resp.status);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"hub\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"version\"") != null);
    }

    {
        const resp = try server.fetch(.{ .path = "/api/nonexistent" });
        defer resp.deinit(std.testing.allocator);
        try std.testing.expectEqual(std.http.Status.not_found, resp.status);
    }
}

test "integration harness covers settings and config round-trips" {
    var server = try IntegrationServer.startWithSeed(std.testing.allocator, struct {
        fn call(srv: *IntegrationServer) !void {
            try seedManagedInstance(srv, "nullboiler", "demo");
        }
    }.call);
    defer server.deinit();

    {
        const resp = try server.fetch(.{ .path = "/api/settings" });
        defer resp.deinit(std.testing.allocator);
        try std.testing.expectEqual(std.http.Status.ok, resp.status);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"port\":") != null);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"access\"") != null);
    }

    {
        const resp = try server.fetch(.{
            .path = "/api/settings",
            .method = .PUT,
            .body = "{\"port\":19901}",
        });
        defer resp.deinit(std.testing.allocator);
        try std.testing.expectEqual(std.http.Status.ok, resp.status);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"status\":\"ok\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"port\":19901") != null);
    }

    {
        const resp = try server.fetch(.{ .path = "/api/instances" });
        defer resp.deinit(std.testing.allocator);
        try std.testing.expectEqual(std.http.Status.ok, resp.status);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"nullboiler\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"demo\"") != null);
    }

    {
        const resp = try server.fetch(.{
            .path = "/api/instances/nullboiler/demo/config",
            .method = .PUT,
            .body = "{\"gateway\":{\"port\":43123},\"provider\":\"openrouter\"}",
        });
        defer resp.deinit(std.testing.allocator);
        try std.testing.expectEqual(std.http.Status.ok, resp.status);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"status\":\"saved\"") != null);
    }

    {
        const resp = try server.fetch(.{ .path = "/api/instances/nullboiler/demo/config" });
        defer resp.deinit(std.testing.allocator);
        try std.testing.expectEqual(std.http.Status.ok, resp.status);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"gateway\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "43123") != null);
    }

    {
        const resp = try server.fetch(.{ .path = "/api/instances/nullboiler/demo/config?path=gateway.port" });
        defer resp.deinit(std.testing.allocator);
        try std.testing.expectEqual(std.http.Status.ok, resp.status);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"path\":\"gateway.port\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"value\":43123") != null);
    }
}

test "integration harness covers instance lifecycle endpoints" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var server = try IntegrationServer.startWithSeed(std.testing.allocator, struct {
        fn call(srv: *IntegrationServer) !void {
            try seedLaunchableGatewayInstance(srv, "nullboiler", "demo", 43123);
        }
    }.call);
    defer server.deinit();

    {
        const resp = try server.fetch(.{ .path = "/api/instances/nullboiler/demo" });
        defer resp.deinit(std.testing.allocator);
        try std.testing.expectEqual(std.http.Status.ok, resp.status);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"status\":\"stopped\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"pid\":") == null);
    }

    {
        const resp = try server.fetch(.{ .path = "/api/instances/nullboiler/demo/start", .method = .POST });
        defer resp.deinit(std.testing.allocator);
        try std.testing.expectEqual(std.http.Status.ok, resp.status);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"status\":\"started\"") != null);
    }

    {
        const resp = try server.fetch(.{ .path = "/api/instances/nullboiler/demo" });
        defer resp.deinit(std.testing.allocator);
        try std.testing.expectEqual(std.http.Status.ok, resp.status);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"status\":\"starting\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"pid\":") != null);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"port\":43123") != null);
    }

    {
        const resp = try server.fetch(.{ .path = "/api/instances/nullboiler/demo/restart", .method = .POST });
        defer resp.deinit(std.testing.allocator);
        try std.testing.expectEqual(std.http.Status.ok, resp.status);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"status\":\"started\"") != null);
    }

    {
        const resp = try server.fetch(.{ .path = "/api/instances/nullboiler/demo" });
        defer resp.deinit(std.testing.allocator);
        try std.testing.expectEqual(std.http.Status.ok, resp.status);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"status\":\"starting\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"pid\":") != null);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"port\":43123") != null);
    }

    {
        const resp = try server.fetch(.{ .path = "/api/instances/nullboiler/demo/stop", .method = .POST });
        defer resp.deinit(std.testing.allocator);
        try std.testing.expectEqual(std.http.Status.ok, resp.status);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"status\":\"stopped\"") != null);
    }

    {
        const resp = try server.fetch(.{ .path = "/api/instances/nullboiler/demo" });
        defer resp.deinit(std.testing.allocator);
        try std.testing.expectEqual(std.http.Status.ok, resp.status);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"status\":\"stopped\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, resp.body, "\"pid\":") == null);
    }
}

test "integration harness covers orchestration proxy not configured" {
    var server = try IntegrationServer.start(std.testing.allocator);
    defer server.deinit();

    const resp = try server.fetch(.{ .path = "/api/orchestration/runs" });
    defer resp.deinit(std.testing.allocator);
    try std.testing.expectEqual(std.http.Status.service_unavailable, resp.status);
    try std.testing.expect(std.mem.indexOf(u8, resp.body, "NullBoiler not configured") != null);
}
