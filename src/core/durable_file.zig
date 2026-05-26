const std = @import("std");
const std_compat = @import("compat");

pub fn writeTextFileAtomically(allocator: std.mem.Allocator, path: []const u8, contents: []const u8) !void {
    const dir_path = std.fs.path.dirname(path) orelse return error.InvalidPath;
    const base_name = std.fs.path.basename(path);
    const tmp_name = try std.fmt.allocPrint(allocator, ".{s}.{x}.tmp", .{
        base_name,
        std_compat.crypto.random.int(u64),
    });
    defer allocator.free(tmp_name);

    const tmp_path = try std.fs.path.join(allocator, &.{ dir_path, tmp_name });
    defer allocator.free(tmp_path);
    errdefer std_compat.fs.deleteFileAbsolute(tmp_path) catch {};

    {
        const file = try std_compat.fs.createFileAbsolute(tmp_path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(contents);
        try file.writeAll("\n");
        try file.sync();
    }

    try std_compat.fs.renameAbsolute(tmp_path, path);
    try syncDirectory(dir_path);
}

pub fn syncDirectory(path: []const u8) !void {
    var dir = try std_compat.fs.openDirAbsolute(path, .{});
    defer dir.close();
    try dir.sync();
}
