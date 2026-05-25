const std = @import("std");
const std_compat = @import("compat");
const net_compat = @import("../net_compat.zig");

const Allocator = std.mem.Allocator;

pub const Response = struct {
    status: []const u8,
    content_type: []const u8,
    body: []const u8,
};

pub const ForwardOptions = struct {
    method: []const u8,
    base_url: []const u8,
    path: []const u8,
    body: []const u8,
    bearer_token: ?[]const u8 = null,
    content_type: []const u8 = "application/json",
    accept: ?[]const u8 = null,
    unreachable_body: []const u8 = "{\"error\":\"upstream unreachable\"}",
};

const LocalBaseUrl = struct {
    host: []const u8,
    port: u16,
};

pub fn isPathInNamespace(target: []const u8, prefix: []const u8) bool {
    return std.mem.eql(u8, target, prefix) or
        (target.len > prefix.len and
            std.mem.startsWith(u8, target, prefix) and
            target[prefix.len] == '/');
}

pub fn forward(allocator: Allocator, opts: ForwardOptions) Response {
    const http_method = parseMethod(opts.method) orelse
        return .{ .status = "405 Method Not Allowed", .content_type = "application/json", .body = "{\"error\":\"method not allowed\"}" };

    const url = std.fmt.allocPrint(allocator, "{s}{s}", .{ opts.base_url, opts.path }) catch
        return .{ .status = "500 Internal Server Error", .content_type = "application/json", .body = "{\"error\":\"internal error\"}" };
    defer allocator.free(url);

    var auth_header: ?[]const u8 = null;
    defer if (auth_header) |value| allocator.free(value);
    var header_buf: [3]std.http.Header = undefined;
    var header_count: usize = 0;
    if (opts.body.len > 0 and opts.content_type.len > 0) {
        header_buf[header_count] = .{ .name = "Content-Type", .value = opts.content_type };
        header_count += 1;
    }
    if (opts.accept) |accept| {
        header_buf[header_count] = .{ .name = "Accept", .value = accept };
        header_count += 1;
    }
    const extra_headers: []const std.http.Header = if (opts.bearer_token) |token| blk: {
        auth_header = std.fmt.allocPrint(allocator, "Bearer {s}", .{token}) catch
            return .{ .status = "500 Internal Server Error", .content_type = "application/json", .body = "{\"error\":\"internal error\"}" };
        header_buf[header_count] = .{ .name = "Authorization", .value = auth_header.? };
        header_count += 1;
        break :blk header_buf[0..header_count];
    } else header_buf[0..header_count];

    var client: std.http.Client = .{ .allocator = allocator, .io = std_compat.io() };
    defer client.deinit();

    var response_body: std.Io.Writer.Allocating = .init(allocator);
    defer response_body.deinit();

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = http_method,
        .payload = if (opts.body.len > 0) opts.body else null,
        .response_writer = &response_body.writer,
        .extra_headers = extra_headers,
    }) catch {
        return .{ .status = "502 Bad Gateway", .content_type = "application/json", .body = opts.unreachable_body };
    };

    const resp_body = response_body.toOwnedSlice() catch
        return .{ .status = "500 Internal Server Error", .content_type = "application/json", .body = "{\"error\":\"internal error\"}" };

    return .{
        .status = mapStatus(@intFromEnum(result.status)),
        .content_type = if (@intFromEnum(result.status) >= 200 and @intFromEnum(result.status) < 300) (opts.accept orelse "application/json") else "application/json",
        .body = resp_body,
    };
}

pub fn forwardStream(allocator: Allocator, opts: ForwardOptions, downstream: std_compat.net.Stream, cors_headers: []const u8) !void {
    _ = parseMethod(opts.method) orelse {
        try writeDirectResponse(downstream, "405 Method Not Allowed", "application/json", "{\"error\":\"method not allowed\"}", cors_headers);
        return;
    };
    const base = parseLocalHttpBaseUrl(opts.base_url) orelse {
        try writeDirectResponse(downstream, "502 Bad Gateway", "application/json", opts.unreachable_body, cors_headers);
        return;
    };

    const upstream = std_compat.net.tcpConnectToHost(allocator, base.host, base.port) catch {
        try writeDirectResponse(downstream, "502 Bad Gateway", "application/json", opts.unreachable_body, cors_headers);
        return;
    };
    defer upstream.close();

    var auth_line: ?[]u8 = null;
    defer if (auth_line) |line| allocator.free(line);
    if (opts.bearer_token) |token| {
        auth_line = try std.fmt.allocPrint(allocator, "Authorization: Bearer {s}\r\n", .{token});
    }

    var accept_line: ?[]u8 = null;
    defer if (accept_line) |line| allocator.free(line);
    if (opts.accept) |accept| {
        accept_line = try std.fmt.allocPrint(allocator, "Accept: {s}\r\n", .{accept});
    }

    const content_type_line = if (opts.body.len > 0 and opts.content_type.len > 0)
        try std.fmt.allocPrint(allocator, "Content-Type: {s}\r\n", .{opts.content_type})
    else
        try allocator.dupe(u8, "");
    defer allocator.free(content_type_line);

    const header = try std.fmt.allocPrint(
        allocator,
        "{s} {s} HTTP/1.1\r\nHost: {s}:{d}\r\n{s}{s}{s}Content-Length: {d}\r\nConnection: close\r\n\r\n",
        .{
            opts.method,
            opts.path,
            base.host,
            base.port,
            content_type_line,
            accept_line orelse "",
            auth_line orelse "",
            opts.body.len,
        },
    );
    defer allocator.free(header);

    try net_compat.streamWriteAll(upstream, header);
    if (opts.body.len > 0) try net_compat.streamWriteAll(upstream, opts.body);

    var header_buf: [64 * 1024]u8 = undefined;
    var header_len: usize = 0;
    var header_end: ?usize = null;
    while (header_end == null) {
        if (header_len == header_buf.len) {
            try writeDirectResponse(downstream, "502 Bad Gateway", "application/json", "{\"error\":\"upstream response headers too large\"}", cors_headers);
            return;
        }
        const n = net_compat.streamRead(upstream, header_buf[header_len..]) catch {
            try writeDirectResponse(downstream, "502 Bad Gateway", "application/json", opts.unreachable_body, cors_headers);
            return;
        };
        if (n == 0) {
            try writeDirectResponse(downstream, "502 Bad Gateway", "application/json", opts.unreachable_body, cors_headers);
            return;
        }
        header_len += n;
        if (std.mem.indexOf(u8, header_buf[0..header_len], "\r\n\r\n")) |pos| {
            header_end = pos;
        }
    }

    const end = header_end.?;
    const upstream_headers = header_buf[0..end];
    const body_start = end + 4;
    const status_code = parseHttpStatusCode(upstream_headers) orelse 502;
    const status = mapStatus(@intCast(@min(status_code, 999)));
    const content_type = extractHttpHeader(upstream_headers, "Content-Type") orelse
        if (status_code >= 200 and status_code < 300) (opts.accept orelse "application/octet-stream") else "application/json";

    try writeStreamingResponseHeaders(downstream, status, content_type, cors_headers);
    if (header_len > body_start) {
        try net_compat.streamWriteAll(downstream, header_buf[body_start..header_len]);
    }

    var buf: [16 * 1024]u8 = undefined;
    while (true) {
        const n = net_compat.streamRead(upstream, &buf) catch return;
        if (n == 0) return;
        try net_compat.streamWriteAll(downstream, buf[0..n]);
    }
}

fn parseLocalHttpBaseUrl(base_url: []const u8) ?LocalBaseUrl {
    const prefix = "http://";
    if (!std.mem.startsWith(u8, base_url, prefix)) return null;
    const rest = base_url[prefix.len..];
    const host_port = if (std.mem.indexOfScalar(u8, rest, '/')) |slash| rest[0..slash] else rest;
    const colon = std.mem.lastIndexOfScalar(u8, host_port, ':') orelse return null;
    const host = host_port[0..colon];
    if (host.len == 0) return null;
    const port = std.fmt.parseInt(u16, host_port[colon + 1 ..], 10) catch return null;
    return .{ .host = host, .port = port };
}

fn parseHttpStatusCode(headers: []const u8) ?u16 {
    const line_end = std.mem.indexOf(u8, headers, "\r\n") orelse headers.len;
    const status_line = headers[0..line_end];
    var parts = std.mem.splitScalar(u8, status_line, ' ');
    _ = parts.next() orelse return null;
    const code_text = parts.next() orelse return null;
    return std.fmt.parseInt(u16, code_text, 10) catch null;
}

fn extractHttpHeader(headers: []const u8, name: []const u8) ?[]const u8 {
    var lines = std.mem.splitSequence(u8, headers, "\r\n");
    _ = lines.next();
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (!std.ascii.eqlIgnoreCase(line[0..colon], name)) continue;
        return std_compat.mem.trimLeft(u8, line[colon + 1 ..], " \t");
    }
    return null;
}

fn writeDirectResponse(stream: std_compat.net.Stream, status: []const u8, content_type: []const u8, body: []const u8, cors_headers: []const u8) !void {
    var buf: [4096]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    try writer.print("HTTP/1.1 {s}\r\n", .{status});
    try writer.print("Content-Type: {s}\r\n", .{content_type});
    try writer.print("Content-Length: {d}\r\n", .{body.len});
    try writer.writeAll(cors_headers);
    try writer.writeAll("Connection: close\r\n\r\n");
    if (body.len <= buf.len - writer.buffered().len) {
        try writer.writeAll(body);
        try net_compat.streamWriteAll(stream, writer.buffered());
        return;
    }
    try net_compat.streamWriteAll(stream, writer.buffered());
    if (body.len > 0) try net_compat.streamWriteAll(stream, body);
}

fn writeStreamingResponseHeaders(stream: std_compat.net.Stream, status: []const u8, content_type: []const u8, cors_headers: []const u8) !void {
    var buf: [4096]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buf);
    try writer.print("HTTP/1.1 {s}\r\n", .{status});
    try writer.print("Content-Type: {s}\r\n", .{content_type});
    try writer.writeAll("Cache-Control: no-cache\r\n");
    try writer.writeAll("X-Accel-Buffering: no\r\n");
    try writer.writeAll(cors_headers);
    try writer.writeAll("Connection: close\r\n\r\n");
    try net_compat.streamWriteAll(stream, writer.buffered());
}

fn parseMethod(method: []const u8) ?std.http.Method {
    if (std.mem.eql(u8, method, "GET")) return .GET;
    if (std.mem.eql(u8, method, "POST")) return .POST;
    if (std.mem.eql(u8, method, "PUT")) return .PUT;
    if (std.mem.eql(u8, method, "DELETE")) return .DELETE;
    if (std.mem.eql(u8, method, "PATCH")) return .PATCH;
    return null;
}

fn mapStatus(code: u10) []const u8 {
    return switch (code) {
        200 => "200 OK",
        201 => "201 Created",
        204 => "204 No Content",
        400 => "400 Bad Request",
        401 => "401 Unauthorized",
        403 => "403 Forbidden",
        404 => "404 Not Found",
        405 => "405 Method Not Allowed",
        409 => "409 Conflict",
        415 => "415 Unsupported Media Type",
        422 => "422 Unprocessable Entity",
        500 => "500 Internal Server Error",
        502 => "502 Bad Gateway",
        503 => "503 Service Unavailable",
        else => if (code >= 200 and code < 300) "200 OK" else if (code >= 400 and code < 500) "400 Bad Request" else "500 Internal Server Error",
    };
}

test "isPathInNamespace matches exact and slash-delimited paths" {
    try std.testing.expect(isPathInNamespace("/api/observability", "/api/observability"));
    try std.testing.expect(isPathInNamespace("/api/observability/v1/runs", "/api/observability"));
    try std.testing.expect(isPathInNamespace("/api/observability/v1/runs?limit=1", "/api/observability"));
    try std.testing.expect(!isPathInNamespace("/api/observability?limit=1", "/api/observability"));
    try std.testing.expect(!isPathInNamespace("/api/observability-extra", "/api/observability"));
    try std.testing.expect(!isPathInNamespace("/api/orchestration", "/api/observability"));
}
