const std = @import("std");

pub const ParsedInstancePathPrefixOwned = struct {
    component: []u8,
    name: []u8,
    suffix: []const u8,

    pub fn deinit(self: ParsedInstancePathPrefixOwned, allocator: std.mem.Allocator) void {
        allocator.free(self.component);
        allocator.free(self.name);
    }
};

pub fn stripTarget(target: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, target, '?')) |idx| {
        return target[0..idx];
    }
    return target;
}

pub fn valueRaw(target: []const u8, key: []const u8) ?[]const u8 {
    const qmark = std.mem.indexOfScalar(u8, target, '?') orelse return null;
    const query = target[qmark + 1 ..];

    var params = std.mem.splitScalar(u8, query, '&');
    while (params.next()) |param| {
        if (std.mem.indexOfScalar(u8, param, '=')) |eq| {
            if (std.mem.eql(u8, param[0..eq], key)) return param[eq + 1 ..];
            continue;
        }
        if (std.mem.eql(u8, param, key)) return "";
    }
    return null;
}

pub fn decodePathSegmentAlloc(allocator: std.mem.Allocator, segment: []const u8) ![]u8 {
    if (!isSafeEncodedPathSegment(segment)) return error.InvalidPathSegment;

    const encoded = try allocator.dupe(u8, segment);
    errdefer allocator.free(encoded);

    const decoded = std.Uri.percentDecodeInPlace(encoded);
    if (!isSafeDecodedPathSegment(decoded)) return error.InvalidPathSegment;
    if (decoded.ptr == encoded.ptr and decoded.len == encoded.len) return encoded;

    const out = try allocator.dupe(u8, decoded);
    allocator.free(encoded);
    return out;
}

pub fn isSafeEncodedPathSegment(segment: []const u8) bool {
    if (segment.len == 0) return false;

    var decoded_len: usize = 0;
    var first: u8 = 0;
    var second: u8 = 0;
    var idx: usize = 0;
    while (idx < segment.len) {
        var byte = segment[idx];
        if (byte == '%') {
            if (idx + 2 >= segment.len) return false;
            const high = hexValue(segment[idx + 1]) orelse return false;
            const low = hexValue(segment[idx + 2]) orelse return false;
            byte = high * 16 + low;
            idx += 3;
        } else {
            idx += 1;
        }

        if (byte == 0 or byte == '/' or byte == '\\') return false;
        if (decoded_len == 0) first = byte;
        if (decoded_len == 1) second = byte;
        decoded_len += 1;
    }

    if (decoded_len == 1 and first == '.') return false;
    if (decoded_len == 2 and first == '.' and second == '.') return false;
    return true;
}

fn hexValue(byte: u8) ?u8 {
    if (byte >= '0' and byte <= '9') return byte - '0';
    if (byte >= 'a' and byte <= 'f') return byte - 'a' + 10;
    if (byte >= 'A' and byte <= 'F') return byte - 'A' + 10;
    return null;
}

fn isSafeDecodedPathSegment(segment: []const u8) bool {
    if (segment.len == 0) return false;
    if (std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..")) return false;
    for (segment) |byte| {
        if (byte == 0 or byte == '/' or byte == '\\') return false;
    }
    return true;
}

pub fn parseInstancePathPrefixAlloc(allocator: std.mem.Allocator, target: []const u8) !?ParsedInstancePathPrefixOwned {
    const clean = stripTarget(target);
    const prefix = "/api/instances/";
    if (!std.mem.startsWith(u8, clean, prefix)) return null;

    const rest = clean[prefix.len..];
    if (rest.len == 0) return null;

    const component_sep = std.mem.indexOfScalar(u8, rest, '/') orelse return null;
    const component_raw = rest[0..component_sep];
    if (component_raw.len == 0) return null;

    const after_component = rest[component_sep + 1 ..];
    if (after_component.len == 0) return null;

    const name_sep = std.mem.indexOfScalar(u8, after_component, '/');
    const name_raw = if (name_sep) |idx| after_component[0..idx] else after_component;
    if (name_raw.len == 0) return null;

    const component = try decodePathSegmentAlloc(allocator, component_raw);
    errdefer allocator.free(component);
    const name = try decodePathSegmentAlloc(allocator, name_raw);
    errdefer allocator.free(name);

    return .{
        .component = component,
        .name = name,
        .suffix = if (name_sep) |idx| after_component[idx + 1 ..] else "",
    };
}

pub fn valueAlloc(allocator: std.mem.Allocator, target: []const u8, key: []const u8) !?[]u8 {
    const raw = valueRaw(target, key) orelse return null;

    const encoded = try allocator.dupe(u8, raw);
    for (encoded) |*ch| {
        if (ch.* == '+') ch.* = ' ';
    }

    const decoded = std.Uri.percentDecodeInPlace(encoded);
    if (decoded.ptr == encoded.ptr and decoded.len == encoded.len) return encoded;

    const out = try allocator.dupe(u8, decoded);
    allocator.free(encoded);
    return out;
}

pub fn boolValue(target: []const u8, key: []const u8) bool {
    const raw = valueRaw(target, key) orelse return false;
    return std.mem.eql(u8, raw, "1") or
        std.ascii.eqlIgnoreCase(raw, "true") or
        std.ascii.eqlIgnoreCase(raw, "yes");
}

pub fn usizeValue(target: []const u8, key: []const u8, default_value: usize) usize {
    const raw = valueRaw(target, key) orelse return default_value;
    return std.fmt.parseInt(usize, raw, 10) catch default_value;
}

test "valueAlloc decodes percent-encoded and plus-separated values" {
    const allocator = std.testing.allocator;
    const value = (try valueAlloc(allocator, "/api/test?query=hello+world%2Fskills", "query")).?;
    defer allocator.free(value);
    try std.testing.expectEqualStrings("hello world/skills", value);
}

test "parseInstancePathPrefixAlloc decodes component and name" {
    const allocator = std.testing.allocator;
    const parsed = (try parseInstancePathPrefixAlloc(allocator, "/api/instances/nullclaw/Opencode%20Go/config")).?;
    defer parsed.deinit(allocator);

    try std.testing.expectEqualStrings("nullclaw", parsed.component);
    try std.testing.expectEqualStrings("Opencode Go", parsed.name);
    try std.testing.expectEqualStrings("config", parsed.suffix);
}

test "parseInstancePathPrefixAlloc decodes additional percent-encoded path characters" {
    const allocator = std.testing.allocator;
    const parsed = (try parseInstancePathPrefixAlloc(
        allocator,
        "/api/instances/nullclaw/NullClaw%20MiMo%20%28beta%29%20%231/channels/web",
    )).?;
    defer parsed.deinit(allocator);

    try std.testing.expectEqualStrings("nullclaw", parsed.component);
    try std.testing.expectEqualStrings("NullClaw MiMo (beta) #1", parsed.name);
    try std.testing.expectEqualStrings("channels/web", parsed.suffix);
}

test "parseInstancePathPrefixAlloc decodes encoded literal percent signs" {
    const allocator = std.testing.allocator;
    const parsed = (try parseInstancePathPrefixAlloc(allocator, "/api/instances/nullclaw/CPU%2050%25/config")).?;
    defer parsed.deinit(allocator);

    try std.testing.expectEqualStrings("CPU 50%", parsed.name);
}

test "parseInstancePathPrefixAlloc rejects decoded path separators" {
    try std.testing.expectError(
        error.InvalidPathSegment,
        parseInstancePathPrefixAlloc(std.testing.allocator, "/api/instances/nullclaw/name%2Fwith%2Fslash/config"),
    );
    try std.testing.expectError(
        error.InvalidPathSegment,
        parseInstancePathPrefixAlloc(std.testing.allocator, "/api/instances/nullclaw/name%5Cwith%5Cslash/config"),
    );
}

test "parseInstancePathPrefixAlloc rejects decoded traversal segments" {
    try std.testing.expectError(
        error.InvalidPathSegment,
        parseInstancePathPrefixAlloc(std.testing.allocator, "/api/instances/nullclaw/%2E%2E/config"),
    );
}

test "parseInstancePathPrefixAlloc rejects malformed percent encodings" {
    try std.testing.expectError(
        error.InvalidPathSegment,
        parseInstancePathPrefixAlloc(std.testing.allocator, "/api/instances/nullclaw/name%/config"),
    );
    try std.testing.expectError(
        error.InvalidPathSegment,
        parseInstancePathPrefixAlloc(std.testing.allocator, "/api/instances/nullclaw/name%2/config"),
    );
    try std.testing.expectError(
        error.InvalidPathSegment,
        parseInstancePathPrefixAlloc(std.testing.allocator, "/api/instances/nullclaw/name%GG/config"),
    );
}

test "boolValue accepts common truthy forms" {
    try std.testing.expect(boolValue("/api/test?stats=1", "stats"));
    try std.testing.expect(boolValue("/api/test?stats=true", "stats"));
    try std.testing.expect(boolValue("/api/test?stats=YES", "stats"));
    try std.testing.expect(!boolValue("/api/test?stats=false", "stats"));
}

test "stripTarget removes query suffix" {
    try std.testing.expectEqualStrings("/api/test", stripTarget("/api/test?foo=bar"));
    try std.testing.expectEqualStrings("/api/test", stripTarget("/api/test"));
}
