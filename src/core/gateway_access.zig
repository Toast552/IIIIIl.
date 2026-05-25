const std = @import("std");
const std_compat = @import("compat");
const paths_mod = @import("paths.zig");

pub const token_prefix = "nullhub-local-";
pub const token_file = ".nullhub-gateway-token";
pub const min_body_size: i64 = 64 * 1024 * 1024;
pub const min_timeout_secs: i64 = 120;

pub fn generateToken(allocator: std.mem.Allocator) ![]u8 {
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

pub fn isNullhubToken(token: []const u8) bool {
    return std.mem.startsWith(u8, token, token_prefix);
}

pub fn tokenPath(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
) ![]u8 {
    const instance_dir = try paths.instanceDir(allocator, component, name);
    defer allocator.free(instance_dir);
    return std.fs.path.join(allocator, &.{ instance_dir, token_file });
}

pub fn readStoredToken(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
) !?[]u8 {
    const path = try tokenPath(allocator, paths, component, name);
    defer allocator.free(path);

    const file = std_compat.fs.openFileAbsolute(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 16 * 1024);
    errdefer allocator.free(contents);
    const trimmed = std.mem.trim(u8, contents, " \t\r\n");
    if (!isNullhubToken(trimmed)) {
        allocator.free(contents);
        return null;
    }
    if (trimmed.len == contents.len) return contents;
    const token = try allocator.dupe(u8, trimmed);
    allocator.free(contents);
    return token;
}

pub fn writeStoredToken(
    allocator: std.mem.Allocator,
    paths: paths_mod.Paths,
    component: []const u8,
    name: []const u8,
    token: []const u8,
) !void {
    const path = try tokenPath(allocator, paths, component, name);
    defer allocator.free(path);

    const file = try std_compat.fs.createFileAbsolute(path, .{ .truncate = true });
    defer file.close();
    if (comptime std_compat.fs.has_executable_bit) file.chmod(0o600) catch {};
    try file.writeAll(token);
    try file.writeAll("\n");
}

pub fn hashTokenAlloc(allocator: std.mem.Allocator, token: []const u8) ![]u8 {
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

pub fn ensurePairedToken(
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

    const token_hash = try hashTokenAlloc(allocator, token);
    defer allocator.free(token_hash);

    if (gateway_obj.getPtr("paired_tokens")) |tokens_value| {
        if (tokens_value.* == .array) {
            var has_hash = false;
            var has_plaintext_nullhub_token = false;
            for (tokens_value.array.items) |item| {
                if (item == .string and std.mem.eql(u8, item.string, token_hash)) {
                    has_hash = true;
                } else if (item == .string and isNullhubToken(item.string)) {
                    has_plaintext_nullhub_token = true;
                }
            }

            if (has_hash and !has_plaintext_nullhub_token) return token;

            var tokens = std.json.Array.init(json_allocator);
            var inserted_hash = false;
            for (tokens_value.array.items) |item| {
                if (item == .string and isNullhubToken(item.string)) continue;
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
