const std = @import("std");
const std_compat = @import("compat");
const durable_file = @import("durable_file.zig");
const paths_mod = @import("paths.zig");

pub const token_prefix = "nullhub-local-";
pub const token_file = ".nullhub-gateway-token";
pub const min_body_size: i64 = 64 * 1024 * 1024;
pub const min_timeout_secs: i64 = 120;

const max_config_bytes = 4 * 1024 * 1024;

pub const Options = struct {
    require_pairing: bool = true,
    max_body_size_bytes: i64 = min_body_size,
    request_timeout_secs: i64 = min_timeout_secs,
    a2a_enabled: bool = true,
    a2a_multi_modal: bool = true,
    stateless_memory: bool = false,
};

pub const Access = struct {
    token: ?[]u8 = null,
    changed: bool = false,

    pub fn deinit(self: *Access, allocator: std.mem.Allocator) void {
        if (self.token) |token| allocator.free(token);
        self.* = .{};
    }
};

pub fn ensureConfig(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
    options: Options,
) !Access {
    if (!std.mem.eql(u8, component, "nullclaw")) return error.UnsupportedComponent;

    const config_path = try paths.instanceConfig(allocator, component, name);
    defer allocator.free(config_path);

    const contents = try readConfigOrEmpty(allocator, config_path);
    defer allocator.free(contents);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, contents, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidConfig;

    const json_allocator = parsed.arena.allocator();
    var changed = false;
    const root = &parsed.value.object;
    const gateway_obj = try ensureObjectField(json_allocator, root, "gateway", &changed);
    const a2a_obj = try ensureObjectField(json_allocator, root, "a2a", &changed);

    try setBoolField(json_allocator, gateway_obj, "require_pairing", options.require_pairing, &changed);
    try setIntegerAtLeast(json_allocator, gateway_obj, "max_body_size_bytes", @max(options.max_body_size_bytes, min_body_size), &changed);
    try setIntegerAtLeast(json_allocator, gateway_obj, "request_timeout_secs", @max(options.request_timeout_secs, min_timeout_secs), &changed);
    try setBoolField(json_allocator, a2a_obj, "enabled", options.a2a_enabled, &changed);
    try setBoolField(json_allocator, a2a_obj, "multi_modal", options.a2a_multi_modal, &changed);

    var token: ?[]u8 = null;
    errdefer if (token) |owned| allocator.free(owned);
    if (options.require_pairing) {
        token = try ensurePairedToken(allocator, json_allocator, paths, component, name, gateway_obj, &changed);
    }

    if (options.stateless_memory) {
        const memory_obj = try ensureObjectField(json_allocator, root, "memory", &changed);
        try setStringField(json_allocator, memory_obj, "profile", "minimal_none", &changed);
        try setStringField(json_allocator, memory_obj, "backend", "none", &changed);
        try setBoolField(json_allocator, memory_obj, "auto_save", false, &changed);
    }

    if (changed) try writeJsonConfigValue(allocator, config_path, parsed.value);

    return .{ .token = token, .changed = changed };
}

pub fn loadAccess(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
) !Access {
    if (!std.mem.eql(u8, component, "nullclaw")) return error.UnsupportedComponent;

    const token = try readStoredToken(allocator, paths, component, name) orelse return error.GatewayTokenMissing;
    errdefer allocator.free(token);

    const config_path = try paths.instanceConfig(allocator, component, name);
    defer allocator.free(config_path);
    const file = try std_compat.fs.openFileAbsolute(config_path, .{});
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, max_config_bytes);
    defer allocator.free(contents);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, contents, .{
        .allocate = .alloc_always,
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidConfig;

    const gateway_value = parsed.value.object.get("gateway") orelse return error.GatewayConfigMissing;
    if (gateway_value != .object) return error.InvalidConfig;
    if (!boolField(gateway_value.object, "require_pairing")) return error.GatewayPairingMissing;

    const token_hash = try hashGatewayTokenAlloc(allocator, token);
    defer allocator.free(token_hash);
    if (!pairedTokensContainHash(gateway_value.object, token_hash)) return error.GatewayPairingMissing;

    return .{ .token = token, .changed = false };
}

pub fn gatewayTokenPath(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
) ![]u8 {
    const instance_dir = try paths.instanceDir(allocator, component, name);
    defer allocator.free(instance_dir);
    return std.fs.path.join(allocator, &.{ instance_dir, token_file });
}

pub fn isNullhubGatewayToken(token: []const u8) bool {
    return std.mem.startsWith(u8, token, token_prefix);
}

pub fn hashGatewayTokenAlloc(allocator: std.mem.Allocator, token: []const u8) ![]u8 {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(token, &digest, .{});
    const hex = "0123456789abcdef";
    var out = try allocator.alloc(u8, digest.len * 2);
    for (digest, 0..) |b, i| {
        out[i * 2] = hex[b >> 4];
        out[i * 2 + 1] = hex[b & 0x0f];
    }
    return out;
}

fn ensureObjectField(
    allocator: std.mem.Allocator,
    obj: *std.json.ObjectMap,
    key: []const u8,
    changed: *bool,
) !*std.json.ObjectMap {
    const gop = try obj.getOrPut(allocator, key);
    if (!gop.found_existing or gop.value_ptr.* != .object) {
        gop.value_ptr.* = .{ .object = .empty };
        changed.* = true;
    }
    return &gop.value_ptr.object;
}

fn setStringField(
    allocator: std.mem.Allocator,
    obj: *std.json.ObjectMap,
    key: []const u8,
    value: []const u8,
    changed: *bool,
) !void {
    if (obj.get(key)) |existing| {
        if (existing == .string and std.mem.eql(u8, existing.string, value)) return;
    }
    try obj.put(allocator, key, .{ .string = try allocator.dupe(u8, value) });
    changed.* = true;
}

fn setBoolField(
    allocator: std.mem.Allocator,
    obj: *std.json.ObjectMap,
    key: []const u8,
    value: bool,
    changed: *bool,
) !void {
    if (obj.get(key)) |existing| {
        if (existing == .bool and existing.bool == value) return;
    }
    try obj.put(allocator, key, .{ .bool = value });
    changed.* = true;
}

fn setIntegerAtLeast(
    allocator: std.mem.Allocator,
    obj: *std.json.ObjectMap,
    key: []const u8,
    minimum: i64,
    changed: *bool,
) !void {
    if (obj.get(key)) |existing| {
        if (existing == .integer and existing.integer >= minimum) return;
    }
    try obj.put(allocator, key, .{ .integer = minimum });
    changed.* = true;
}

fn generateToken(allocator: std.mem.Allocator) ![]u8 {
    var random_bytes: [24]u8 = undefined;
    std_compat.crypto.random.bytes(&random_bytes);
    const hex = "0123456789abcdef";
    var token = try allocator.alloc(u8, token_prefix.len + random_bytes.len * 2);
    @memcpy(token[0..token_prefix.len], token_prefix);
    for (random_bytes, 0..) |b, i| {
        token[token_prefix.len + i * 2] = hex[b >> 4];
        token[token_prefix.len + i * 2 + 1] = hex[b & 0x0f];
    }
    return token;
}

fn readStoredToken(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
) !?[]u8 {
    const path = try gatewayTokenPath(allocator, paths, component, name);
    defer allocator.free(path);

    const file = std_compat.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 16 * 1024);
    errdefer allocator.free(contents);
    const trimmed = std.mem.trim(u8, contents, " \t\r\n");
    if (!isNullhubGatewayToken(trimmed)) {
        allocator.free(contents);
        return null;
    }
    if (trimmed.len == contents.len) return contents;
    const token = try allocator.dupe(u8, trimmed);
    allocator.free(contents);
    return token;
}

fn readConfigOrEmpty(allocator: std.mem.Allocator, config_path: []const u8) ![]u8 {
    const file = std_compat.fs.openFileAbsolute(config_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return allocator.dupe(u8, "{}"),
        else => return err,
    };
    defer file.close();
    return try file.readToEndAlloc(allocator, max_config_bytes);
}

fn writeStoredToken(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
    token: []const u8,
) !void {
    const path = try gatewayTokenPath(allocator, paths, component, name);
    defer allocator.free(path);

    try durable_file.writeTextFileAtomicallyWithMode(allocator, path, token, 0o600);
}

fn ensurePairedToken(
    allocator: std.mem.Allocator,
    json_allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
    gateway_obj: *std.json.ObjectMap,
    changed: *bool,
) ![]u8 {
    const token = blk: {
        if (try readStoredToken(allocator, paths, component, name)) |stored| {
            break :blk stored;
        }
        const generated = try generateToken(allocator);
        errdefer allocator.free(generated);
        try writeStoredToken(allocator, paths, component, name, generated);
        break :blk generated;
    };
    errdefer allocator.free(token);

    const token_hash = try hashGatewayTokenAlloc(allocator, token);
    defer allocator.free(token_hash);

    if (gateway_obj.getPtr("paired_tokens")) |tokens_value| {
        if (tokens_value.* == .array) {
            var has_hash = false;
            var has_plaintext_nullhub_token = false;
            for (tokens_value.array.items) |item| {
                if (item == .string and std.mem.eql(u8, item.string, token_hash)) {
                    has_hash = true;
                } else if (item == .string and isNullhubGatewayToken(item.string)) {
                    has_plaintext_nullhub_token = true;
                }
            }

            if (has_hash and !has_plaintext_nullhub_token) return token;

            var tokens = std.json.Array.init(json_allocator);
            var inserted_hash = false;
            for (tokens_value.array.items) |item| {
                if (item == .string and isNullhubGatewayToken(item.string)) continue;
                if (item == .string and std.mem.eql(u8, item.string, token_hash)) {
                    if (inserted_hash) continue;
                    inserted_hash = true;
                }
                try tokens.append(item);
            }
            if (!inserted_hash) {
                try tokens.append(.{ .string = try json_allocator.dupe(u8, token_hash) });
            }
            tokens_value.* = .{ .array = tokens };
            changed.* = true;
            return token;
        }
    }

    var tokens = std.json.Array.init(json_allocator);
    try tokens.append(.{ .string = try json_allocator.dupe(u8, token_hash) });
    try gateway_obj.put(json_allocator, "paired_tokens", .{ .array = tokens });
    changed.* = true;
    return token;
}

fn pairedTokensContainHash(gateway_obj: std.json.ObjectMap, token_hash: []const u8) bool {
    const tokens_value = gateway_obj.get("paired_tokens") orelse return false;
    if (tokens_value != .array) return false;
    for (tokens_value.array.items) |item| {
        if (item == .string and std.mem.eql(u8, item.string, token_hash)) return true;
    }
    return false;
}

fn boolField(obj: std.json.ObjectMap, key: []const u8) bool {
    const value = obj.get(key) orelse return false;
    return value == .bool and value.bool;
}

fn writeJsonConfigValue(allocator: std.mem.Allocator, config_path: []const u8, value: std.json.Value) !void {
    const rendered = try std.json.Stringify.valueAlloc(allocator, value, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false,
    });
    defer allocator.free(rendered);

    try durable_file.writeTextFileAtomically(allocator, config_path, rendered);
}

test "ensureConfig creates missing nullclaw config" {
    const test_helpers = @import("../test_helpers.zig");
    const allocator = std.testing.allocator;
    var fixture = try test_helpers.TempPaths.init(allocator);
    defer fixture.deinit();
    try fixture.paths.ensureDirs();

    const instance_dir = try fixture.paths.instanceDir(allocator, "nullclaw", "hat");
    defer allocator.free(instance_dir);
    try std_compat.fs.cwd().makePath(instance_dir);

    var access = try ensureConfig(allocator, fixture.paths, "nullclaw", "hat", .{});
    defer access.deinit(allocator);
    try std.testing.expect(access.changed);
    try std.testing.expect(access.token != null);

    var loaded = try loadAccess(allocator, fixture.paths, "nullclaw", "hat");
    defer loaded.deinit(allocator);
    try std.testing.expectEqualStrings(access.token.?, loaded.token.?);
}
