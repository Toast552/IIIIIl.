const std = @import("std");
const std_compat = @import("compat");
const paths_mod = @import("paths.zig");
const state_mod = @import("state.zig");
const test_helpers = @import("../test_helpers.zig");

pub const NullTicketsConfig = struct {
    name: []const u8,
    port: u16 = 7700,
    api_token: ?[]const u8 = null,
};

pub const NullWatchConfig = struct {
    name: []const u8,
    host: []const u8 = "127.0.0.1",
    port: u16 = 7710,
    api_token: ?[]const u8 = null,
};

pub const NullBoilerWorkflowConfig = struct {
    file_name: []const u8,
    pipeline_id: []const u8,
    claim_role: []const u8,
    success_trigger: []const u8,
};

pub const managed_workflow_file_name = "nullhub-tracker-workflow.json";
pub const legacy_workflow_file_name = "tracker-workflow.json";
pub const default_tracker_prompt_template =
    "Task {{task.id}}: {{task.title}}\n\n{{task.description}}\n\nMetadata:\n{{task.metadata}}";

pub const NullBoilerTrackerConfig = struct {
    url: []const u8,
    api_token: ?[]const u8 = null,
    agent_id: []const u8 = "nullboiler",
    workflows_dir: []const u8 = "workflows",
    max_concurrent_tasks: u32 = 10,
    workflow: ?NullBoilerWorkflowConfig = null,
};

pub const NullBoilerConfig = struct {
    name: []const u8,
    port: u16 = 8080,
    api_token: ?[]const u8 = null,
    tracker: ?NullBoilerTrackerConfig = null,
};

pub const NullBoilerTrackerLinkOptions = struct {
    tickets: NullTicketsConfig,
    pipeline_id: []const u8,
    claim_role: []const u8,
    success_trigger: []const u8,
    max_concurrent_tasks: ?u32 = null,
};

pub const NullClawTelemetryLink = struct {
    configured: bool = false,
    endpoint: ?[]u8 = null,
    service_name: ?[]u8 = null,
    auth_configured: bool = false,
    source_header_configured: bool = false,

    pub fn deinit(self: *NullClawTelemetryLink, allocator: std.mem.Allocator) void {
        if (self.endpoint) |value| allocator.free(value);
        if (self.service_name) |value| allocator.free(value);
        self.* = .{};
    }
};

pub fn listNullTickets(allocator: std.mem.Allocator, state: *state_mod.State, paths: paths_mod.Paths) ![]NullTicketsConfig {
    const names = try state.instanceNames("nulltickets") orelse return allocator.alloc(NullTicketsConfig, 0);
    defer state.allocator.free(names);
    var list: std.ArrayListUnmanaged(NullTicketsConfig) = .empty;
    errdefer deinitNullTicketsConfigs(allocator, list.items);
    defer list.deinit(allocator);

    for (names) |name| {
        if (try loadNullTicketsConfig(allocator, paths, name)) |cfg| {
            var owned = cfg;
            errdefer deinitNullTicketsConfig(allocator, &owned);
            try list.append(allocator, owned);
        }
    }

    return list.toOwnedSlice(allocator);
}

pub fn listNullWatch(allocator: std.mem.Allocator, state: *state_mod.State, paths: paths_mod.Paths) ![]NullWatchConfig {
    const names = try state.instanceNames("nullwatch") orelse return allocator.alloc(NullWatchConfig, 0);
    defer state.allocator.free(names);
    var list: std.ArrayListUnmanaged(NullWatchConfig) = .empty;
    errdefer deinitNullWatchConfigs(allocator, list.items);
    defer list.deinit(allocator);

    for (names) |name| {
        if (try loadNullWatchConfig(allocator, paths, name)) |cfg| {
            var owned = cfg;
            errdefer deinitNullWatchConfig(allocator, &owned);
            try list.append(allocator, owned);
        }
    }

    return list.toOwnedSlice(allocator);
}

pub fn listNullBoilers(allocator: std.mem.Allocator, state: *state_mod.State, paths: paths_mod.Paths) ![]NullBoilerConfig {
    const names = try state.instanceNames("nullboiler") orelse return allocator.alloc(NullBoilerConfig, 0);
    defer state.allocator.free(names);
    var list: std.ArrayListUnmanaged(NullBoilerConfig) = .empty;
    errdefer deinitNullBoilerConfigs(allocator, list.items);
    defer list.deinit(allocator);

    for (names) |name| {
        if (try loadNullBoilerConfig(allocator, paths, name)) |cfg| {
            var owned = cfg;
            errdefer deinitNullBoilerConfig(allocator, &owned);
            try list.append(allocator, owned);
        }
    }

    return list.toOwnedSlice(allocator);
}

pub fn loadNullTicketsConfig(allocator: std.mem.Allocator, paths: paths_mod.Paths, name: []const u8) !?NullTicketsConfig {
    const config_path = paths.instanceConfig(allocator, "nulltickets", name) catch return null;
    defer allocator.free(config_path);

    const file = std_compat.fs.openFileAbsolute(config_path, .{}) catch return null;
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(bytes);
    const parsed = std.json.parseFromSlice(NullTicketsConfigFile, allocator, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return null;
    defer parsed.deinit();

    return .{
        .name = try allocator.dupe(u8, name),
        .port = parsed.value.port,
        .api_token = if (parsed.value.api_token) |token| try allocator.dupe(u8, token) else null,
    };
}

pub fn loadNullWatchConfig(allocator: std.mem.Allocator, paths: paths_mod.Paths, name: []const u8) !?NullWatchConfig {
    const config_path = paths.instanceConfig(allocator, "nullwatch", name) catch return null;
    defer allocator.free(config_path);

    const file = std_compat.fs.openFileAbsolute(config_path, .{}) catch return null;
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(bytes);
    const parsed = std.json.parseFromSlice(NullWatchConfigFile, allocator, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return null;
    defer parsed.deinit();

    return .{
        .name = try allocator.dupe(u8, name),
        .host = try allocator.dupe(u8, parsed.value.host),
        .port = parsed.value.port,
        .api_token = if (parsed.value.api_token) |token| try allocator.dupe(u8, token) else null,
    };
}

pub fn loadNullBoilerConfig(allocator: std.mem.Allocator, paths: paths_mod.Paths, name: []const u8) !?NullBoilerConfig {
    const config_path = paths.instanceConfig(allocator, "nullboiler", name) catch return null;
    defer allocator.free(config_path);

    const file = std_compat.fs.openFileAbsolute(config_path, .{}) catch return null;
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(bytes);
    const parsed = std.json.parseFromSlice(NullBoilerConfigFile, allocator, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return null;
    defer parsed.deinit();

    const config_dir = std.fs.path.dirname(config_path) orelse return null;

    var cfg = NullBoilerConfig{
        .name = try allocator.dupe(u8, name),
        .port = parsed.value.port,
    };
    errdefer deinitNullBoilerConfig(allocator, &cfg);
    if (parsed.value.api_token) |token| {
        cfg.api_token = try allocator.dupe(u8, token);
    }

    if (parsed.value.tracker) |tracker| {
        cfg.tracker = try loadNullBoilerTrackerConfig(allocator, config_dir, tracker);
    }

    return cfg;
}

fn loadNullBoilerTrackerConfig(
    allocator: std.mem.Allocator,
    config_dir: []const u8,
    tracker: NullBoilerTrackerConfigFile,
) !NullBoilerTrackerConfig {
    const tracker_url = try allocator.dupe(u8, tracker.url orelse "");
    errdefer allocator.free(tracker_url);
    const tracker_api_token = if (tracker.api_token) |token| try allocator.dupe(u8, token) else null;
    errdefer if (tracker_api_token) |token| allocator.free(token);
    const tracker_agent_id = try allocator.dupe(u8, tracker.agent_id);
    errdefer allocator.free(tracker_agent_id);
    const tracker_workflows_dir = try resolveRelativePath(allocator, config_dir, tracker.workflows_dir);
    errdefer allocator.free(tracker_workflows_dir);
    const tracker_workflow = try loadPrimaryWorkflowConfig(allocator, tracker_workflows_dir);

    return .{
        .url = tracker_url,
        .api_token = tracker_api_token,
        .agent_id = tracker_agent_id,
        .workflows_dir = tracker_workflows_dir,
        .max_concurrent_tasks = tracker.concurrency.max_concurrent_tasks,
        .workflow = tracker_workflow,
    };
}

pub fn deinitNullTicketsConfig(allocator: std.mem.Allocator, cfg: *NullTicketsConfig) void {
    allocator.free(cfg.name);
    if (cfg.api_token) |token| allocator.free(token);
    cfg.* = undefined;
}

pub fn deinitNullTicketsConfigs(allocator: std.mem.Allocator, configs: []NullTicketsConfig) void {
    for (configs) |*cfg| deinitNullTicketsConfig(allocator, cfg);
    allocator.free(configs);
}

pub fn deinitNullWatchConfig(allocator: std.mem.Allocator, cfg: *NullWatchConfig) void {
    allocator.free(cfg.name);
    allocator.free(cfg.host);
    if (cfg.api_token) |token| allocator.free(token);
    cfg.* = undefined;
}

pub fn deinitNullWatchConfigs(allocator: std.mem.Allocator, configs: []NullWatchConfig) void {
    for (configs) |*cfg| deinitNullWatchConfig(allocator, cfg);
    allocator.free(configs);
}

pub fn deinitNullBoilerConfig(allocator: std.mem.Allocator, cfg: *NullBoilerConfig) void {
    allocator.free(cfg.name);
    if (cfg.api_token) |token| allocator.free(token);
    if (cfg.tracker) |*tracker| {
        allocator.free(tracker.url);
        if (tracker.api_token) |token| allocator.free(token);
        allocator.free(tracker.agent_id);
        allocator.free(tracker.workflows_dir);
        if (tracker.workflow) |*workflow| {
            allocator.free(workflow.file_name);
            allocator.free(workflow.pipeline_id);
            allocator.free(workflow.claim_role);
            allocator.free(workflow.success_trigger);
        }
    }
    cfg.* = undefined;
}

pub fn deinitNullBoilerConfigs(allocator: std.mem.Allocator, configs: []NullBoilerConfig) void {
    for (configs) |*cfg| deinitNullBoilerConfig(allocator, cfg);
    allocator.free(configs);
}

pub fn matchNullTicketsTarget(boiler_cfg: NullBoilerConfig, tickets: []const NullTicketsConfig) ?NullTicketsConfig {
    const tracker = boiler_cfg.tracker orelse return null;
    const tracker_port = extractLocalPort(tracker.url) orelse return null;

    for (tickets) |ticket| {
        if (ticket.port == tracker_port) return ticket;
    }
    return null;
}

pub fn countLinkedBoilersForTickets(tickets_cfg: NullTicketsConfig, boilers: []const NullBoilerConfig) usize {
    var count: usize = 0;
    for (boilers) |boiler| {
        const target = matchNullTicketsTarget(boiler, &.{tickets_cfg}) orelse continue;
        _ = target;
        count += 1;
    }
    return count;
}

pub fn loadNullClawTelemetryLink(allocator: std.mem.Allocator, paths: paths_mod.Paths, name: []const u8) !NullClawTelemetryLink {
    const config_path = try paths.instanceConfig(allocator, "nullclaw", name);
    defer allocator.free(config_path);

    const file = std_compat.fs.openFileAbsolute(config_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.NotFound,
        else => return err,
    };
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(bytes);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    return try parseNullClawTelemetryLink(allocator, parsed.value);
}

pub fn linkNullClawToNullWatch(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    claw_name: []const u8,
    watch_cfg: NullWatchConfig,
) !void {
    const config_path = try paths.instanceConfig(allocator, "nullclaw", claw_name);
    defer allocator.free(config_path);

    const file = std_compat.fs.openFileAbsolute(config_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.NotFound,
        else => return err,
    };
    defer file.close();

    const config_bytes = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(config_bytes);

    var parsed_config = try std.json.parseFromSlice(std.json.Value, allocator, config_bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
    defer parsed_config.deinit();
    if (parsed_config.value != .object) return error.InvalidConfig;

    const diagnostics_map = try ensureObjectField(allocator, &parsed_config.value.object, "diagnostics");
    try diagnostics_map.put(allocator, "backend", .{ .string = "otel" });

    const otel_map = try ensureObjectField(allocator, diagnostics_map, "otel");
    const endpoint = try buildNullWatchEndpoint(allocator, watch_cfg);
    try otel_map.put(allocator, "endpoint", .{ .string = endpoint });

    const should_default_service = blk: {
        const service_name = jsonString(otel_map.*, "service_name") orelse break :blk true;
        break :blk service_name.len == 0 or std.mem.eql(u8, service_name, "nullclaw");
    };
    if (should_default_service) {
        const service_name = try std.fmt.allocPrint(allocator, "nullclaw/{s}", .{claw_name});
        try otel_map.put(allocator, "service_name", .{ .string = service_name });
    }

    const headers_map = try ensureObjectField(allocator, otel_map, "headers");
    try headers_map.put(allocator, "x-nullwatch-source", .{ .string = "nullclaw" });
    if (watch_cfg.api_token) |token| {
        const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{token});
        try headers_map.put(allocator, "Authorization", .{ .string = auth_header });
    } else {
        _ = headers_map.swapRemove("Authorization");
    }

    const rendered = try std.json.Stringify.valueAlloc(allocator, parsed_config.value, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false,
    });
    defer allocator.free(rendered);

    const out = try std_compat.fs.createFileAbsolute(config_path, .{ .truncate = true });
    defer out.close();
    try out.writeAll(rendered);
    try out.writeAll("\n");
}

pub fn linkNullBoilerToNullTickets(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    boiler_name: []const u8,
    options: NullBoilerTrackerLinkOptions,
) !void {
    var existing = try loadNullBoilerConfig(allocator, paths, boiler_name) orelse return error.NotFound;
    defer deinitNullBoilerConfig(allocator, &existing);

    const config_path = try paths.instanceConfig(allocator, "nullboiler", boiler_name);
    defer allocator.free(config_path);

    const original_config_bytes = blk: {
        const file = std_compat.fs.openFileAbsolute(config_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return error.NotFound,
            else => return err,
        };
        defer file.close();
        break :blk try file.readToEndAlloc(allocator, 1024 * 1024);
    };
    defer allocator.free(original_config_bytes);

    var parsed_config = try std.json.parseFromSlice(std.json.Value, allocator, original_config_bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
    defer parsed_config.deinit();
    if (parsed_config.value != .object) return error.InvalidConfig;

    const config_allocator = parsed_config.arena.allocator();
    const tracker_map = try ensureObjectField(config_allocator, &parsed_config.value.object, "tracker");

    const tracker_url = try std.fmt.allocPrint(config_allocator, "http://127.0.0.1:{d}", .{options.tickets.port});
    try tracker_map.put(config_allocator, "url", .{ .string = tracker_url });
    if (options.tickets.api_token) |token| {
        try tracker_map.put(config_allocator, "api_token", .{ .string = try config_allocator.dupe(u8, token) });
    } else {
        _ = tracker_map.swapRemove("api_token");
    }

    const default_agent_id = if (existing.tracker) |tracker| tracker.agent_id else boiler_name;
    const agent_id = nonEmptyJsonStringOrDefault(tracker_map.*, "agent_id", default_agent_id);
    try tracker_map.put(config_allocator, "agent_id", .{ .string = try config_allocator.dupe(u8, agent_id) });

    const workflows_dir_config = nonEmptyJsonStringOrDefault(tracker_map.*, "workflows_dir", "workflows");
    try tracker_map.put(config_allocator, "workflows_dir", .{ .string = try config_allocator.dupe(u8, workflows_dir_config) });

    const concurrency_map = try ensureObjectField(config_allocator, tracker_map, "concurrency");
    if (options.max_concurrent_tasks) |max_concurrent_tasks| {
        try concurrency_map.put(config_allocator, "max_concurrent_tasks", .{ .integer = max_concurrent_tasks });
    } else if (concurrency_map.get("max_concurrent_tasks") == null) {
        try concurrency_map.put(config_allocator, "max_concurrent_tasks", .{ .integer = if (existing.tracker) |tracker| tracker.max_concurrent_tasks else 1 });
    }

    const workflows_dir = try resolvePathFromConfigPath(allocator, config_path, workflows_dir_config);
    defer allocator.free(workflows_dir);

    try writeJsonConfigValue(allocator, config_path, parsed_config.value);

    ensureNullBoilerTrackerWorkflowFile(
        allocator,
        config_path,
        workflows_dir,
        options.pipeline_id,
        options.claim_role,
        options.success_trigger,
    ) catch |err| {
        writeBytes(config_path, original_config_bytes) catch {};
        return err;
    };
}

pub fn findNullWatchByEndpoint(watches: []const NullWatchConfig, endpoint: ?[]const u8) ?NullWatchConfig {
    const value = endpoint orelse return null;
    const port = nullWatchEndpointPort(value) orelse return null;
    for (watches) |watch| {
        if (watch.port == port) return watch;
    }
    return null;
}

pub fn buildNullWatchEndpoint(allocator: std.mem.Allocator, watch: NullWatchConfig) ![]u8 {
    const host = normalizedConnectHost(watch.host);
    if (std.mem.indexOfScalar(u8, host, ':') != null and !std.mem.startsWith(u8, host, "[")) {
        return std.fmt.allocPrint(allocator, "http://[{s}]:{d}", .{ host, watch.port });
    }
    return std.fmt.allocPrint(allocator, "http://{s}:{d}", .{ host, watch.port });
}

pub fn extractLocalPort(url: []const u8) ?u16 {
    const uri = std.Uri.parse(url) catch return null;
    const host = uri.host orelse return null;
    const port = uri.port orelse return null;

    return switch (host) {
        .raw => |value| if (isLocalHost(value)) port else null,
        else => null,
    };
}

fn parseNullClawTelemetryLink(allocator: std.mem.Allocator, config: std.json.Value) !NullClawTelemetryLink {
    const diagnostics = diagnosticsObject(config) orelse return .{};
    const backend = jsonString(diagnostics, "backend") orelse "";
    const backend_configured = std.mem.eql(u8, backend, "otel") or std.mem.eql(u8, backend, "otlp");

    var endpoint: ?[]const u8 = null;
    var service_name: ?[]const u8 = null;
    if (objectField(diagnostics, "otel")) |otel| {
        endpoint = jsonString(otel, "endpoint");
        service_name = jsonString(otel, "service_name");
    }

    const headers = telemetryHeadersObject(diagnostics);
    const auth_configured = if (headers) |map| jsonString(map, "Authorization") != null else false;
    const source_header_configured = if (headers) |map| jsonString(map, "x-nullwatch-source") != null else false;

    return .{
        .configured = backend_configured and endpoint != null,
        .endpoint = if (endpoint) |value| try allocator.dupe(u8, value) else null,
        .service_name = if (service_name) |value| try allocator.dupe(u8, value) else null,
        .auth_configured = auth_configured,
        .source_header_configured = source_header_configured,
    };
}

fn objectField(obj: std.json.ObjectMap, key: []const u8) ?std.json.ObjectMap {
    const value = obj.get(key) orelse return null;
    return if (value == .object) value.object else null;
}

fn diagnosticsObject(config: std.json.Value) ?std.json.ObjectMap {
    if (config != .object) return null;
    return objectField(config.object, "diagnostics");
}

fn telemetryHeadersObject(diagnostics: std.json.ObjectMap) ?std.json.ObjectMap {
    if (objectField(diagnostics, "otel")) |otel| {
        if (objectField(otel, "headers")) |headers| return headers;
    }
    return null;
}

fn nullWatchEndpointPort(endpoint: []const u8) ?u16 {
    if (extractLocalPort(endpoint)) |port| return port;
    const uri = std.Uri.parse(endpoint) catch return null;
    return uri.port;
}

fn normalizedConnectHost(host: []const u8) []const u8 {
    if (host.len == 0 or
        std.mem.eql(u8, host, "0.0.0.0") or
        std.mem.eql(u8, host, "::") or
        std.mem.eql(u8, host, "[::]") or
        std.mem.eql(u8, host, "localhost"))
    {
        return "127.0.0.1";
    }
    return host;
}

fn isLocalHost(host: []const u8) bool {
    return std.mem.eql(u8, host, "127.0.0.1") or
        std.mem.eql(u8, host, "localhost") or
        std.mem.eql(u8, host, "0.0.0.0") or
        std.mem.eql(u8, host, "::1");
}

fn jsonString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = obj.get(key) orelse return null;
    return if (value == .string) value.string else null;
}

fn nonEmptyJsonStringOrDefault(obj: std.json.ObjectMap, key: []const u8, default_value: []const u8) []const u8 {
    const value = jsonString(obj, key) orelse return default_value;
    return if (value.len > 0) value else default_value;
}

fn ensureObjectField(
    allocator: std.mem.Allocator,
    parent: *std.json.ObjectMap,
    key: []const u8,
) !*std.json.ObjectMap {
    if (parent.getPtr(key)) |value_ptr| {
        if (value_ptr.* != .object) {
            value_ptr.* = .{ .object = .empty };
        }
        return &value_ptr.object;
    }

    try parent.put(allocator, key, .{ .object = .empty });
    return &parent.getPtr(key).?.object;
}

fn writeBytes(path: []const u8, bytes: []const u8) !void {
    const out = try std_compat.fs.createFileAbsolute(path, .{ .truncate = true });
    defer out.close();
    try out.writeAll(bytes);
}

fn writeJsonConfigValue(allocator: std.mem.Allocator, config_path: []const u8, value: std.json.Value) !void {
    const rendered = try std.json.Stringify.valueAlloc(allocator, value, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false,
    });
    defer allocator.free(rendered);

    const out = try std_compat.fs.createFileAbsolute(config_path, .{ .truncate = true });
    defer out.close();
    try out.writeAll(rendered);
    try out.writeAll("\n");
}

fn resolvePathFromConfigPath(allocator: std.mem.Allocator, config_path: []const u8, value: []const u8) ![]const u8 {
    if (value.len == 0 or std.fs.path.isAbsolute(value)) return allocator.dupe(u8, value);
    const config_dir = std.fs.path.dirname(config_path) orelse return error.InvalidPath;
    return std.fs.path.resolve(allocator, &.{ config_dir, value });
}

fn ensurePath(path: []const u8) !void {
    if (path.len == 0) return error.InvalidPath;
    try std_compat.fs.cwd().makePath(path);
}

fn ensureNullBoilerTrackerWorkflowFile(
    allocator: std.mem.Allocator,
    config_path: []const u8,
    workflows_dir: []const u8,
    pipeline_id: []const u8,
    claim_role: []const u8,
    success_trigger: []const u8,
) !void {
    try ensurePath(workflows_dir);

    const workflow_path = try std.fs.path.join(allocator, &.{ workflows_dir, managed_workflow_file_name });
    defer allocator.free(workflow_path);

    const workflow_id = try std.fmt.allocPrint(allocator, "wf-{s}-{s}", .{ pipeline_id, claim_role });
    defer allocator.free(workflow_id);

    const rendered = try std.json.Stringify.valueAlloc(allocator, .{
        .id = workflow_id,
        .pipeline_id = pipeline_id,
        .claim_roles = &.{claim_role},
        .execution = "subprocess",
        .prompt_template = default_tracker_prompt_template,
        .on_success = .{
            .transition_to = success_trigger,
        },
    }, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false,
    });
    defer allocator.free(rendered);

    try writeTextFileAtomically(allocator, workflow_path, rendered);

    deleteStaleNullHubManagedWorkflows(allocator, workflows_dir) catch {};

    const config_dir = std.fs.path.dirname(config_path) orelse return error.InvalidPath;
    const legacy_path = try std.fs.path.join(allocator, &.{ config_dir, legacy_workflow_file_name });
    defer allocator.free(legacy_path);
    std_compat.fs.deleteFileAbsolute(legacy_path) catch {};

    const legacy_workflows_path = try std.fs.path.join(allocator, &.{ workflows_dir, legacy_workflow_file_name });
    defer allocator.free(legacy_workflows_path);
    std_compat.fs.deleteFileAbsolute(legacy_workflows_path) catch {};
}

fn writeTextFileAtomically(allocator: std.mem.Allocator, path: []const u8, contents: []const u8) !void {
    const tmp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{path});
    defer allocator.free(tmp_path);
    errdefer std_compat.fs.deleteFileAbsolute(tmp_path) catch {};

    {
        const file_out = try std_compat.fs.createFileAbsolute(tmp_path, .{ .truncate = true });
        defer file_out.close();
        try file_out.writeAll(contents);
        try file_out.writeAll("\n");
    }

    try std_compat.fs.renameAbsolute(tmp_path, path);
}

fn deleteStaleNullHubManagedWorkflows(allocator: std.mem.Allocator, workflows_dir: []const u8) !void {
    var dir = try std_compat.fs.openDirAbsolute(workflows_dir, .{ .iterate = true });
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
        if (std.mem.eql(u8, entry.name, managed_workflow_file_name)) continue;

        const workflow_path = try std.fs.path.join(allocator, &.{ workflows_dir, entry.name });
        if (isNullHubManagedWorkflow(allocator, workflow_path)) {
            std_compat.fs.deleteFileAbsolute(workflow_path) catch {};
        }
        allocator.free(workflow_path);
    }
}

fn isNullHubManagedWorkflow(
    allocator: std.mem.Allocator,
    workflow_path: []const u8,
) bool {
    const file = std_compat.fs.openFileAbsolute(workflow_path, .{}) catch return false;
    defer file.close();

    const bytes = file.readToEndAlloc(allocator, 1024 * 1024) catch return false;
    defer allocator.free(bytes);

    const parsed = std.json.parseFromSlice(struct {
        id: []const u8 = "",
        execution: []const u8 = "",
        prompt_template: ?[]const u8 = null,
    }, allocator, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return false;
    defer parsed.deinit();

    return std.mem.startsWith(u8, parsed.value.id, "wf-") and
        std.mem.eql(u8, parsed.value.execution, "subprocess") and
        parsed.value.prompt_template != null and
        std.mem.eql(u8, parsed.value.prompt_template.?, default_tracker_prompt_template);
}

fn loadPrimaryWorkflowConfig(allocator: std.mem.Allocator, workflows_dir: []const u8) !?NullBoilerWorkflowConfig {
    var dir = std_compat.fs.openDirAbsolute(workflows_dir, .{ .iterate = true }) catch return null;
    defer dir.close();

    const managed_path = try std.fs.path.join(allocator, &.{ workflows_dir, managed_workflow_file_name });
    defer allocator.free(managed_path);
    if (std_compat.fs.openFileAbsolute(managed_path, .{})) |managed_file| {
        managed_file.close();
        return loadWorkflowConfigFromFile(allocator, workflows_dir, managed_workflow_file_name);
    } else |_| {}

    var best_name: ?[]const u8 = null;
    defer if (best_name) |value| allocator.free(value);

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
        if (best_name == null or std.mem.order(u8, entry.name, best_name.?) == .lt) {
            if (best_name) |value| allocator.free(value);
            best_name = try allocator.dupe(u8, entry.name);
        }
    }

    const file_name = best_name orelse return null;
    return loadWorkflowConfigFromFile(allocator, workflows_dir, file_name);
}

fn loadWorkflowConfigFromFile(allocator: std.mem.Allocator, workflows_dir: []const u8, file_name: []const u8) !?NullBoilerWorkflowConfig {
    const workflow_path = try std.fs.path.join(allocator, &.{ workflows_dir, file_name });
    defer allocator.free(workflow_path);
    const file = std_compat.fs.openFileAbsolute(workflow_path, .{}) catch return null;
    defer file.close();

    const bytes = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(bytes);
    const parsed = std.json.parseFromSlice(WorkflowFile, allocator, bytes, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    }) catch return null;
    defer parsed.deinit();

    const file_name_owned = try allocator.dupe(u8, file_name);
    errdefer allocator.free(file_name_owned);
    const pipeline_id = try allocator.dupe(u8, parsed.value.pipeline_id);
    errdefer allocator.free(pipeline_id);
    const claim_role = try allocator.dupe(u8, if (parsed.value.claim_roles.len > 0) parsed.value.claim_roles[0] else "");
    errdefer allocator.free(claim_role);
    const success_trigger = try allocator.dupe(u8, if (parsed.value.on_success) |cfg| cfg.transition_to else "");

    return .{
        .file_name = file_name_owned,
        .pipeline_id = pipeline_id,
        .claim_role = claim_role,
        .success_trigger = success_trigger,
    };
}

fn resolveRelativePath(allocator: std.mem.Allocator, base_dir: []const u8, value: []const u8) ![]const u8 {
    if (value.len == 0 or std.fs.path.isAbsolute(value)) return allocator.dupe(u8, value);
    return std.fs.path.resolve(allocator, &.{ base_dir, value });
}

const NullTicketsConfigFile = struct {
    port: u16 = 7700,
    api_token: ?[]const u8 = null,
};

const NullWatchConfigFile = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 7710,
    api_token: ?[]const u8 = null,
};

const NullBoilerTrackerConfigFile = struct {
    url: ?[]const u8 = null,
    api_token: ?[]const u8 = null,
    agent_id: []const u8 = "nullboiler",
    concurrency: struct {
        max_concurrent_tasks: u32 = 10,
    } = .{},
    workflows_dir: []const u8 = "workflows",
};

const NullBoilerConfigFile = struct {
    port: u16 = 8080,
    api_token: ?[]const u8 = null,
    tracker: ?NullBoilerTrackerConfigFile = null,
};

const WorkflowFile = struct {
    pipeline_id: []const u8,
    claim_roles: []const []const u8 = &.{},
    on_success: ?struct {
        transition_to: []const u8 = "",
    } = null,
};

test "loadNullBoilerConfig accepts tracker without url" {
    const allocator = std.testing.allocator;
    var fixture = try test_helpers.TempPaths.init(allocator);
    defer fixture.deinit();
    try fixture.paths.ensureDirs();

    const inst_dir = try fixture.paths.instanceDir(allocator, "nullboiler", "worker-a");
    defer allocator.free(inst_dir);
    try std.fs.makePathAbsolute(inst_dir);

    const config_path = try fixture.paths.instanceConfig(allocator, "nullboiler", "worker-a");
    defer allocator.free(config_path);
    const file = try std_compat.fs.createFileAbsolute(config_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll("{\"port\":8811,\"tracker\":{\"agent_id\":\"worker-a\"}}\n");

    var cfg = (try loadNullBoilerConfig(allocator, fixture.paths, "worker-a")).?;
    defer deinitNullBoilerConfig(allocator, &cfg);

    try std.testing.expectEqual(@as(u16, 8811), cfg.port);
    try std.testing.expect(cfg.tracker != null);
    try std.testing.expectEqualStrings("", cfg.tracker.?.url);
    try std.testing.expectEqualStrings("worker-a", cfg.tracker.?.agent_id);
}

test "linkNullBoilerToNullTickets preserves custom tracker config and replaces generated workflows" {
    const allocator = std.testing.allocator;
    var fixture = try test_helpers.TempPaths.init(allocator);
    defer fixture.deinit();
    try fixture.paths.ensureDirs();

    const inst_dir = try fixture.paths.instanceDir(allocator, "nullboiler", "worker-a");
    defer allocator.free(inst_dir);
    try ensurePath(inst_dir);

    const config_path = try fixture.paths.instanceConfig(allocator, "nullboiler", "worker-a");
    defer allocator.free(config_path);
    {
        const file = try std_compat.fs.createFileAbsolute(config_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            "{\"port\":8811,\"tracker\":{\"url\":\"http://127.0.0.1:7701\",\"api_token\":\"old-token\",\"agent_id\":\"custom-agent\",\"workflows_dir\":\"custom-workflows\",\"poll_interval_ms\":9000,\"concurrency\":{\"max_concurrent_tasks\":7,\"per_pipeline\":{\"pipe-old\":2}}}}\n",
        );
    }

    const workflows_dir = try std.fs.path.join(allocator, &.{ inst_dir, "custom-workflows" });
    defer allocator.free(workflows_dir);
    try ensurePath(workflows_dir);

    const manual_workflow_path = try std.fs.path.join(allocator, &.{ workflows_dir, "manual.json" });
    defer allocator.free(manual_workflow_path);
    {
        const file = try std_compat.fs.createFileAbsolute(manual_workflow_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(
            \\{
            \\  "id": "wf-manual",
            \\  "pipeline_id": "pipe-manual",
            \\  "claim_roles": ["reviewer"],
            \\  "execution": "subprocess",
            \\  "prompt_template": "Manual workflow",
            \\  "on_success": { "transition_to": "approved" }
            \\}
            \\
        );
    }

    const stale_workflow_path = try std.fs.path.join(allocator, &.{ workflows_dir, "pipe-old.json" });
    defer allocator.free(stale_workflow_path);
    {
        const rendered = try std.json.Stringify.valueAlloc(allocator, .{
            .id = "wf-pipe-old-coder",
            .pipeline_id = "pipe-old",
            .claim_roles = &.{"coder"},
            .execution = "subprocess",
            .prompt_template = default_tracker_prompt_template,
            .on_success = .{
                .transition_to = "complete",
            },
        }, .{
            .whitespace = .indent_2,
            .emit_null_optional_fields = false,
        });
        defer allocator.free(rendered);

        const file = try std_compat.fs.createFileAbsolute(stale_workflow_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(rendered);
        try file.writeAll("\n");
    }

    try linkNullBoilerToNullTickets(allocator, fixture.paths, "worker-a", .{
        .tickets = .{ .name = "tracker-a", .port = 7711, .api_token = "admin-token" },
        .pipeline_id = "pipe-dev",
        .claim_role = "reviewer",
        .success_trigger = "complete",
        .max_concurrent_tasks = null,
    });

    const config_bytes = try std.fs.readFileAbsolute(allocator, config_path, 1024 * 1024);
    defer allocator.free(config_bytes);
    try std.testing.expect(std.mem.indexOf(u8, config_bytes, "\"url\": \"http://127.0.0.1:7711\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, config_bytes, "\"api_token\": \"admin-token\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, config_bytes, "\"agent_id\": \"custom-agent\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, config_bytes, "\"workflows_dir\": \"custom-workflows\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, config_bytes, "\"poll_interval_ms\": 9000") != null);
    try std.testing.expect(std.mem.indexOf(u8, config_bytes, "\"per_pipeline\"") != null);

    const managed_workflow_path = try std.fs.path.join(allocator, &.{ workflows_dir, managed_workflow_file_name });
    defer allocator.free(managed_workflow_path);
    const managed_bytes = try std.fs.readFileAbsolute(allocator, managed_workflow_path, 1024 * 1024);
    defer allocator.free(managed_bytes);
    try std.testing.expect(std.mem.indexOf(u8, managed_bytes, "\"pipeline_id\": \"pipe-dev\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, managed_bytes, "\"reviewer\"") != null);

    const manual_file = try std_compat.fs.openFileAbsolute(manual_workflow_path, .{});
    manual_file.close();
    try std.testing.expectError(error.FileNotFound, std_compat.fs.openFileAbsolute(stale_workflow_path, .{}));
}

test "linkNullBoilerToNullTickets restores config when workflow generation fails" {
    const allocator = std.testing.allocator;
    var fixture = try test_helpers.TempPaths.init(allocator);
    defer fixture.deinit();
    try fixture.paths.ensureDirs();

    const inst_dir = try fixture.paths.instanceDir(allocator, "nullboiler", "worker-a");
    defer allocator.free(inst_dir);
    try ensurePath(inst_dir);

    const config_path = try fixture.paths.instanceConfig(allocator, "nullboiler", "worker-a");
    defer allocator.free(config_path);
    const original_config =
        "{\"port\":8811,\"tracker\":{\"url\":\"http://127.0.0.1:7701\",\"workflows_dir\":\"blocked-workflows\",\"concurrency\":{\"max_concurrent_tasks\":4}}}\n";
    {
        const file = try std_compat.fs.createFileAbsolute(config_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(original_config);
    }

    const blocked_path = try std.fs.path.join(allocator, &.{ inst_dir, "blocked-workflows" });
    defer allocator.free(blocked_path);
    {
        const file = try std_compat.fs.createFileAbsolute(blocked_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll("not a directory\n");
    }

    linkNullBoilerToNullTickets(allocator, fixture.paths, "worker-a", .{
        .tickets = .{ .name = "tracker-a", .port = 7711, .api_token = null },
        .pipeline_id = "pipe-dev",
        .claim_role = "coder",
        .success_trigger = "complete",
        .max_concurrent_tasks = 2,
    }) catch {
        const restored = try std.fs.readFileAbsolute(allocator, config_path, 1024 * 1024);
        defer allocator.free(restored);
        try std.testing.expectEqualStrings(original_config, restored);
        return;
    };
    return error.ExpectedWorkflowGenerationFailure;
}

test "linkNullBoilerToNullTickets keeps stale workflow when replacement write fails" {
    const allocator = std.testing.allocator;
    var fixture = try test_helpers.TempPaths.init(allocator);
    defer fixture.deinit();
    try fixture.paths.ensureDirs();

    const inst_dir = try fixture.paths.instanceDir(allocator, "nullboiler", "worker-a");
    defer allocator.free(inst_dir);
    try ensurePath(inst_dir);

    const config_path = try fixture.paths.instanceConfig(allocator, "nullboiler", "worker-a");
    defer allocator.free(config_path);
    const original_config =
        "{\"port\":8811,\"tracker\":{\"url\":\"http://127.0.0.1:7701\",\"workflows_dir\":\"workflows\",\"concurrency\":{\"max_concurrent_tasks\":4}}}\n";
    {
        const file = try std_compat.fs.createFileAbsolute(config_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(original_config);
    }

    const workflows_dir = try std.fs.path.join(allocator, &.{ inst_dir, "workflows" });
    defer allocator.free(workflows_dir);
    try ensurePath(workflows_dir);

    const stale_workflow_path = try std.fs.path.join(allocator, &.{ workflows_dir, "pipe-old.json" });
    defer allocator.free(stale_workflow_path);
    {
        const rendered = try std.json.Stringify.valueAlloc(allocator, .{
            .id = "wf-pipe-old-coder",
            .pipeline_id = "pipe-old",
            .claim_roles = &.{"coder"},
            .execution = "subprocess",
            .prompt_template = default_tracker_prompt_template,
            .on_success = .{
                .transition_to = "complete",
            },
        }, .{
            .whitespace = .indent_2,
            .emit_null_optional_fields = false,
        });
        defer allocator.free(rendered);

        const file = try std_compat.fs.createFileAbsolute(stale_workflow_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(rendered);
        try file.writeAll("\n");
    }

    const managed_workflow_path = try std.fs.path.join(allocator, &.{ workflows_dir, managed_workflow_file_name });
    defer allocator.free(managed_workflow_path);
    try ensurePath(managed_workflow_path);

    linkNullBoilerToNullTickets(allocator, fixture.paths, "worker-a", .{
        .tickets = .{ .name = "tracker-a", .port = 7711, .api_token = null },
        .pipeline_id = "pipe-dev",
        .claim_role = "coder",
        .success_trigger = "complete",
        .max_concurrent_tasks = 2,
    }) catch {
        const restored = try std.fs.readFileAbsolute(allocator, config_path, 1024 * 1024);
        defer allocator.free(restored);
        try std.testing.expectEqualStrings(original_config, restored);

        const stale_file = try std_compat.fs.openFileAbsolute(stale_workflow_path, .{});
        stale_file.close();
        return;
    };
    return error.ExpectedWorkflowGenerationFailure;
}
