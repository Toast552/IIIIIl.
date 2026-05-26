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
    max_response_bytes: ?usize = null,
};

const LimitedResponseBody = struct {
    body: std.Io.Writer.Allocating,
    writer: std.Io.Writer,
    limit: usize,
    written: usize = 0,
    too_large: bool = false,

    fn init(allocator: Allocator, max_response_bytes: ?usize) LimitedResponseBody {
        return .{
            .body = .init(allocator),
            .writer = .{
                .vtable = &vtable,
                .buffer = &.{},
            },
            .limit = max_response_bytes orelse std.math.maxInt(usize),
        };
    }

    fn deinit(self: *LimitedResponseBody) void {
        self.body.deinit();
    }

    fn toOwnedSlice(self: *LimitedResponseBody) Allocator.Error![]u8 {
        return try self.body.toOwnedSlice();
    }

    const vtable: std.Io.Writer.VTable = .{
        .drain = drain,
        .flush = flush,
    };

    fn drain(writer: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *LimitedResponseBody = @fieldParentPtr("writer", writer);
        if (data.len == 0) return 0;
        const total = std.Io.Writer.countSplat(data, splat);
        const next_written = std.math.add(usize, self.written, total) catch {
            self.too_large = true;
            return error.WriteFailed;
        };
        if (next_written > self.limit) {
            self.too_large = true;
            return error.WriteFailed;
        }

        for (data[0 .. data.len - 1]) |bytes| {
            self.body.writer.writeAll(bytes) catch return error.WriteFailed;
        }
        const pattern = data[data.len - 1];
        for (0..splat) |_| {
            self.body.writer.writeAll(pattern) catch return error.WriteFailed;
        }
        self.written = next_written;
        return total;
    }

    fn flush(writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const self: *LimitedResponseBody = @fieldParentPtr("writer", writer);
        try self.body.writer.flush();
    }
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

    var response_body = LimitedResponseBody.init(allocator, opts.max_response_bytes);
    defer response_body.deinit();

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = http_method,
        .payload = if (opts.body.len > 0) opts.body else null,
        .response_writer = &response_body.writer,
        .extra_headers = extra_headers,
    }) catch |err| switch (err) {
        error.WriteFailed => if (response_body.too_large)
            return .{ .status = "502 Bad Gateway", .content_type = "application/json", .body = "{\"error\":\"upstream response too large\"}" }
        else
            return .{ .status = "500 Internal Server Error", .content_type = "application/json", .body = "{\"error\":\"internal error\"}" },
        else => return .{ .status = "502 Bad Gateway", .content_type = "application/json", .body = opts.unreachable_body },
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
    const http_method = parseMethod(opts.method) orelse {
        try writeDirectResponse(downstream, "405 Method Not Allowed", "application/json", "{\"error\":\"method not allowed\"}", cors_headers);
        return;
    };
    const url = try std.fmt.allocPrint(allocator, "{s}{s}", .{ opts.base_url, opts.path });
    defer allocator.free(url);
    const uri = std.Uri.parse(url) catch {
        try writeDirectResponse(downstream, "502 Bad Gateway", "application/json", opts.unreachable_body, cors_headers);
        return;
    };

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
        auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{token});
        header_buf[header_count] = .{ .name = "Authorization", .value = auth_header.? };
        header_count += 1;
        break :blk header_buf[0..header_count];
    } else header_buf[0..header_count];

    var client: std.http.Client = .{ .allocator = allocator, .io = std_compat.io() };
    defer client.deinit();

    var request = client.request(http_method, uri, .{
        .redirect_behavior = .unhandled,
        .keep_alive = false,
        .headers = .{
            .accept_encoding = .omit,
            .connection = .{ .override = "close" },
        },
        .extra_headers = extra_headers,
    }) catch {
        try writeDirectResponse(downstream, "502 Bad Gateway", "application/json", opts.unreachable_body, cors_headers);
        return;
    };
    defer request.deinit();

    if (http_method.requestHasBody()) {
        request.transfer_encoding = .{ .content_length = opts.body.len };
        var body_buffer: [8192]u8 = undefined;
        var body_writer = request.sendBodyUnflushed(&body_buffer) catch {
            try writeDirectResponse(downstream, "502 Bad Gateway", "application/json", opts.unreachable_body, cors_headers);
            return;
        };
        body_writer.writer.writeAll(opts.body) catch {
            try writeDirectResponse(downstream, "502 Bad Gateway", "application/json", opts.unreachable_body, cors_headers);
            return;
        };
        body_writer.end() catch {
            try writeDirectResponse(downstream, "502 Bad Gateway", "application/json", opts.unreachable_body, cors_headers);
            return;
        };
        request.connection.?.flush() catch {
            try writeDirectResponse(downstream, "502 Bad Gateway", "application/json", opts.unreachable_body, cors_headers);
            return;
        };
    } else {
        request.sendBodiless() catch {
            try writeDirectResponse(downstream, "502 Bad Gateway", "application/json", opts.unreachable_body, cors_headers);
            return;
        };
    }

    var response = request.receiveHead(&.{}) catch {
        try writeDirectResponse(downstream, "502 Bad Gateway", "application/json", opts.unreachable_body, cors_headers);
        return;
    };
    const status_code = @intFromEnum(response.head.status);
    const content_type = response.head.content_type orelse
        if (status_code >= 200 and status_code < 300) (opts.accept orelse "application/octet-stream") else "application/json";

    try writeStreamingResponseHeaders(downstream, mapStatus(status_code), content_type, cors_headers);

    var transfer_buffer: [64]u8 = undefined;
    const reader = response.reader(&transfer_buffer);
    var read_buf: [16 * 1024]u8 = undefined;
    while (true) {
        const n = reader.readSliceShort(&read_buf) catch |err| {
            std.log.warn("upstream stream read failed: {s}", .{@errorName(err)});
            return;
        };
        if (n == 0) return;
        try net_compat.streamWriteAll(downstream, read_buf[0..n]);
    }
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
        100 => "100 Continue",
        101 => "101 Switching Protocols",
        102 => "102 Processing",
        103 => "103 Early Hints",
        200 => "200 OK",
        201 => "201 Created",
        202 => "202 Accepted",
        203 => "203 Non-Authoritative Information",
        204 => "204 No Content",
        205 => "205 Reset Content",
        206 => "206 Partial Content",
        207 => "207 Multi-Status",
        208 => "208 Already Reported",
        226 => "226 IM Used",
        300 => "300 Multiple Choices",
        301 => "301 Moved Permanently",
        302 => "302 Found",
        303 => "303 See Other",
        304 => "304 Not Modified",
        305 => "305 Use Proxy",
        307 => "307 Temporary Redirect",
        308 => "308 Permanent Redirect",
        400 => "400 Bad Request",
        401 => "401 Unauthorized",
        402 => "402 Payment Required",
        403 => "403 Forbidden",
        404 => "404 Not Found",
        405 => "405 Method Not Allowed",
        406 => "406 Not Acceptable",
        407 => "407 Proxy Authentication Required",
        408 => "408 Request Timeout",
        409 => "409 Conflict",
        410 => "410 Gone",
        411 => "411 Length Required",
        412 => "412 Precondition Failed",
        413 => "413 Payload Too Large",
        414 => "414 URI Too Long",
        415 => "415 Unsupported Media Type",
        416 => "416 Range Not Satisfiable",
        417 => "417 Expectation Failed",
        418 => "418 I'm a Teapot",
        421 => "421 Misdirected Request",
        422 => "422 Unprocessable Entity",
        423 => "423 Locked",
        424 => "424 Failed Dependency",
        425 => "425 Too Early",
        426 => "426 Upgrade Required",
        428 => "428 Precondition Required",
        429 => "429 Too Many Requests",
        431 => "431 Request Header Fields Too Large",
        451 => "451 Unavailable For Legal Reasons",
        500 => "500 Internal Server Error",
        501 => "501 Not Implemented",
        502 => "502 Bad Gateway",
        503 => "503 Service Unavailable",
        504 => "504 Gateway Timeout",
        505 => "505 HTTP Version Not Supported",
        506 => "506 Variant Also Negotiates",
        507 => "507 Insufficient Storage",
        508 => "508 Loop Detected",
        510 => "510 Not Extended",
        511 => "511 Network Authentication Required",
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

test "mapStatus preserves common upstream status codes" {
    try std.testing.expectEqualStrings("202 Accepted", mapStatus(202));
    try std.testing.expectEqualStrings("206 Partial Content", mapStatus(206));
    try std.testing.expectEqualStrings("429 Too Many Requests", mapStatus(429));
    try std.testing.expectEqualStrings("504 Gateway Timeout", mapStatus(504));
}
