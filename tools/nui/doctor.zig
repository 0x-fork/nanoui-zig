//! `nui doctor`: what a nanoui app needs, checked. Zig 0.17, and on Linux
//! GTK 3 (loaded when an app starts); macOS and Windows need nothing more.
const std = @import("std");
const builtin = @import("builtin");
const cli = @import("main.zig");

pub fn run(a: std.mem.Allocator, io: std.Io, out: *cli.Out) !void {
    const r = std.process.run(a, io, .{ .argv = &.{ "zig", "version" } }) catch null;
    const zig_version = if (r) |x| std.mem.trim(u8, x.stdout, " \r\n") else "";
    const zig_ok = std.mem.startsWith(u8, zig_version, "0.17.");
    const gtk_ok = if (builtin.os.tag == .linux) gtk() else true;
    const os = @tagName(builtin.os.tag);
    if (zig_ok) out.step("✓ zig {s}", .{zig_version}) else out.step("✗ zig {s} (nanoui needs 0.17)", .{if (zig_version.len > 0) zig_version else "not found"});
    if (builtin.os.tag == .linux) {
        if (gtk_ok) out.step("✓ GTK 3", .{}) else out.step("✗ GTK 3 not found (libgtk-3-0)", .{});
    }
    out.step("✓ {s} {s}", .{ os, @tagName(builtin.cpu.arch) });
    if (!zig_ok) return out.fail("zig 0.17 is needed", .{}, "install it from ziglang.org/download, or with zigup 0.17.0");
    if (!gtk_ok) return out.fail("GTK 3 is needed on Linux", .{}, "sudo apt install libgtk-3-0 (or your distribution's GTK 3)");
    out.done(.{ .zig = zig_version, .os = os, .arch = @tagName(builtin.cpu.arch) }, &.{});
}

fn gtk() bool {
    var lib = std.DynLib.open("libgtk-3.so.0") catch return false;
    lib.close();
    return true;
}
