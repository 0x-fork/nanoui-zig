//! HTTP requests, answered on the main thread: the system's own client
//! on macOS and iOS (NSURLSession: its TLS, proxies, caches and
//! certificates), so an app need bring none. Not yet on Linux and
//! Windows, where `fetch` answers with an error.
//!
//!     nanoui.http.fetch(gpa, .{ .url = "https://example.com/data.json" }, state, State.loaded);
//!
//!     fn loaded(s: *State, r: nanoui.http.Response) void {
//!         if (r.status == 200) s.parse(r.body);
//!         s.window.redraw();
//!     }
const std = @import("std");
const builtin = @import("builtin");
const apple = builtin.os.tag == .macos or builtin.os.tag == .ios;
const objc = if (apple) @import("objc.zig") else struct {};

pub const Header = struct { name: []const u8, value: []const u8 };

pub const Request = struct {
    url: []const u8,
    method: []const u8 = "GET",
    headers: []const Header = &.{},
    body: []const u8 = "",
    /// Seconds without a byte before it gives up.
    timeout: f64 = 30,
};

pub const Response = struct {
    /// The HTTP status: 0 when no answer came (`err` says why).
    status: u16,
    /// Valid until the callback returns: copy what is kept.
    body: []const u8,
    /// Why there was no answer (offline, a bad certificate, a timeout).
    err: []const u8 = "",
};

/// Sends `req` and calls `done(ctx, response)` on the main thread when it
/// is answered or fails. `req`'s bytes are copied: they need not outlive
/// the call.
pub fn fetch(gpa: std.mem.Allocator, req: Request, ctx: anytype, comptime done: fn (@TypeOf(ctx), Response) void) void {
    const P = Pending(@TypeOf(ctx), done);
    const p = gpa.create(P) catch return done(ctx, .{ .status = 0, .body = "", .err = "out of memory" });
    p.* = .{ .gpa = gpa, .ctx = ctx };
    if (!apple) {
        p.err = "nanoui.http: not on this platform yet";
        return P.deliver(p);
    }
    const pool = objc.Pool.push();
    defer pool.pop();
    const url = objc.msg(?objc.Object, objc.class("NSURL"), "URLWithString:", .{objc.nsString(req.url)}) orelse {
        p.err = "not a URL";
        return P.deliver(p);
    };
    const r = objc.msg(objc.Object, objc.class("NSMutableURLRequest"), "requestWithURL:", .{url});
    objc.msg(void, r, "setHTTPMethod:", .{objc.nsString(req.method)});
    objc.msg(void, r, "setTimeoutInterval:", .{req.timeout});
    for (req.headers) |h| objc.msg(void, r, "setValue:forHTTPHeaderField:", .{ objc.nsString(h.value), objc.nsString(h.name) });
    if (req.body.len > 0) {
        const data = objc.msg(objc.Object, objc.class("NSData"), "dataWithBytes:length:", .{ req.body.ptr, @as(objc.NSUInteger, req.body.len) });
        objc.msg(void, r, "setHTTPBody:", .{data});
    }
    const session = objc.msg(objc.Object, objc.class("NSURLSession"), "sharedSession", .{});
    // The session copies the block (and with it `p`), and calls it on a
    // queue of its own.
    var block = objc.Block(P, &.{ ?objc.Object, ?objc.Object, ?objc.Object }).init(p, P.answered);
    const task = objc.msg(objc.Object, session, "dataTaskWithRequest:completionHandler:", .{ r, @as(*anyopaque, @ptrCast(&block)) });
    objc.msg(void, task, "resume", .{});
}

fn Pending(comptime Ctx: type, comptime done: fn (Ctx, Response) void) type {
    return struct {
        gpa: std.mem.Allocator,
        ctx: Ctx,
        status: u16 = 0,
        body: []u8 = &.{},
        err: []const u8 = "",
        err_owned: bool = false,

        const Self = @This();

        /// On the session's queue: the answer copied, then taken to the main thread.
        fn answered(p: *Self, data: ?objc.Object, response: ?objc.Object, err: ?objc.Object) void {
            const pool = objc.Pool.push();
            defer pool.pop();
            if (response) |res| {
                if (objc.msg(objc.BOOL, res, "isKindOfClass:", .{objc.class("NSHTTPURLResponse")}) != objc.NO)
                    p.status = @intCast(std.math.clamp(objc.msg(objc.NSInteger, res, "statusCode", .{}), 0, 999));
            }
            if (data) |d| {
                const len = objc.msg(objc.NSUInteger, d, "length", .{});
                if (len > 0) if (p.gpa.alloc(u8, len)) |body| {
                    const bytes = objc.msg(?[*]const u8, d, "bytes", .{});
                    if (bytes) |b| @memcpy(body, b[0..len]);
                    p.body = body;
                } else |_| {
                    p.err = "out of memory";
                };
            }
            if (err) |e| {
                const why = objc.fromNSString(objc.msg(?objc.Object, e, "localizedDescription", .{}));
                if (p.gpa.dupe(u8, why)) |copy| {
                    p.err = copy;
                    p.err_owned = true;
                } else |_| p.err = "failed";
                p.status = 0;
            }
            objc.dispatchMain(p, deliverC);
        }

        fn deliverC(context: ?*anyopaque) callconv(.c) void {
            deliver(@ptrCast(@alignCast(context.?)));
        }

        fn deliver(p: *Self) void {
            done(p.ctx, .{ .status = p.status, .body = p.body, .err = p.err });
            p.gpa.free(p.body);
            if (p.err_owned) p.gpa.free(p.err);
            p.gpa.destroy(p);
        }
    };
}

test "a request is answered on the main thread, its body copied" {
    if (!apple) return error.SkipZigTest;
    const State = struct {
        body: [16]u8 = undefined,
        len: usize = 0,
        answered: bool = false,
        on_main: bool = false,
        fn done(s: *@This(), r: Response) void {
            s.answered = true;
            s.on_main = objc.isMainThread();
            s.len = @min(r.body.len, s.body.len);
            @memcpy(s.body[0..s.len], r.body[0..s.len]);
        }
    };
    var s: State = .{};
    // A data URL: answered by the system's client without the network.
    fetch(std.testing.allocator, .{ .url = "data:text/plain,hello%20zig" }, &s, State.done);
    var waited: f64 = 0;
    while (!s.answered and waited < 5) : (waited += 0.01) @import("platform.zig").runFor(0.01);
    try std.testing.expect(s.answered);
    try std.testing.expect(s.on_main);
    try std.testing.expectEqualStrings("hello zig", s.body[0..s.len]);
}
