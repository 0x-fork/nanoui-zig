//! A 30-second reel of `ui.motion` at work in nanotrade, a mock trading
//! app drawn by nanoui (scenes.zig): it runs in a Tester, offscreen, 30 frames a second, and each
//! frame's pixels go to standard output for ffmpeg. A script moves the
//! pointer and clicks as a person would, through the Tester alone: no
//! window shows and nothing reaches the screen or the mouse.
//!
//!     zig build reel && zig-out/bin/nanoui-reel | ffmpeg -f rawvideo \
//!       -pix_fmt bgra -s 1920x1080 -r 30 -i - -pix_fmt yuv420p out.mp4
//!     zig-out/bin/nanoui-reel --still=4.5:/tmp/frame.png   # one frame
//!     zig-out/bin/nanoui-reel --cues    # when clicks and cuts come
//!     zig-out/bin/nanoui-reel --dark
//!
//! tools/reel.sh adds the sounds and a soundtrack.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const scenes = @import("scenes.zig");
const Director = scenes.Director;
const at = scenes.at;

const fps = 30;
const scale = 1.5;

const Target = union(enum) {
    point: [2]f32,
    text: []const u8,
    /// Beside a text: the + of the shares' input, right of its value.
    beside: struct { text: []const u8, dx: f32 },
};

const Act = enum { none, click, buy, place, dismiss };

const Move = struct { at: f32, dur: f32, to: Target, act: Act = .none };

const moves = [_]Move{
    .{ .at = at.ranges + 0.3, .dur = 0.7, .to = .{ .text = "1W" }, .act = .click },
    .{ .at = at.ranges + 1.9, .dur = 0.4, .to = .{ .text = "1M" }, .act = .click },
    .{ .at = at.ranges + 3.1, .dur = 0.4, .to = .{ .text = "1Y" }, .act = .click },
    // Across the chart, the crosshair following.
    .{ .at = at.hover + 0.1, .dur = 0.8, .to = .{ .point = .{ 380, 360 } } },
    .{ .at = at.hover + 1.0, .dur = 1.4, .to = .{ .point = .{ 640, 300 } } },
    .{ .at = at.hover + 2.5, .dur = 1.2, .to = .{ .point = .{ 900, 250 } } },
    .{ .at = at.hover + 3.8, .dur = 0.8, .to = .{ .point = .{ 1080, 220 } } },
    .{ .at = at.order + 0.1, .dur = 0.6, .to = .{ .text = "Buy NVDA" }, .act = .buy },
    .{ .at = at.order + 1.3, .dur = 0.6, .to = .{ .beside = .{ .text = "10", .dx = 53 } }, .act = .click },
    .{ .at = at.order + 2.05, .dur = 0.15, .to = .{ .beside = .{ .text = "20", .dx = 53 } }, .act = .click },
    .{ .at = at.order + 2.45, .dur = 0.15, .to = .{ .beside = .{ .text = "30", .dx = 53 } }, .act = .click },
    .{ .at = at.order + 3.0, .dur = 0.5, .to = .{ .text = "Place order" }, .act = .place },
    .{ .at = at.alert + 1.0, .dur = 0.5, .to = .{ .text = "Dismiss" }, .act = .dismiss },
};

/// When the pointer shows.
const shown = [_][2]f32{ .{ at.ranges + 0.1, at.ranges + 3.9 }, .{ at.hover, at.hover + 4.9 }, .{ at.order, at.order + 4.0 }, .{ at.alert + 0.6, at.alert + 1.8 } };

/// What happens without a click, and when.
fn events(d: *Director, now: f32, prev: f32) void {
    const crossed = struct {
        fn f(p: f32, n: f32, t: f32) bool {
            return p < t and n >= t;
        }
    }.f;
    // A tick every 0.35 s, leaning toward a path that crosses 186 just
    // before the alert.
    var t: f32 = at.ticks;
    while (t < at.end) : (t += 0.35) if (crossed(prev, now, t)) {
        const before = d.market.price;
        const goal = 182.4 + (186.5 - 182.4) * std.math.clamp((t - at.ticks) / (at.alert - 0.3 - at.ticks), 0, 1);
        d.market.tick((goal - d.market.price) * 0.25);
        d.last_up = d.market.price >= before;
        d.tick_at = now;
    };
    d.crosshair = now >= at.hover and now < at.hover + 5;
    if (crossed(prev, now, at.order + 4.3)) {
        d.placing = false;
        d.filled = true;
        d.entry = d.market.price - 0.4;
        d.toaster.push(.{ .status = .success, .title = "Order filled", .message = "Bought 40 NVDA at market.", .duration = 3.0 });
    }
    if (crossed(prev, now, at.sort - 0.4)) d.order_open = false;
    if (crossed(prev, now, at.sort + 0.4)) d.sorted = true;
    if (crossed(prev, now, at.sort + 2.0)) {
        d.market.watch[3].change = -0.92;
        d.market.watch[4].change = 2.31;
    }
    if (crossed(prev, now, at.alert)) d.alert = true;
    if (crossed(prev, now, at.end)) d.receding = true;
}

/// The times sounds go with: clicks, chimes for the fill and the alert,
/// air as the window opens, the panel slides in and the end comes.
fn cues(io: std.Io) !void {
    var buf: [4096]u8 = undefined;
    var w = std.Io.File.stdout().writer(io, &buf);
    const o = &w.interface;
    for (moves) |m| if (m.act != .none) try o.print("click {d:.3}\n", .{m.at + m.dur});
    for ([_]f32{ at.order + 4.3, at.alert }) |t| try o.print("chime {d:.3}\n", .{t});
    for ([_]f32{ 0.4, at.order + 0.7, at.end }) |t| try o.print("cut {d:.3}\n", .{t});
    try o.flush();
}

const Script = struct {
    next: usize = 0,
    started: ?usize = null,
    start: [2]f32 = .{ 0, 0 },
    to: [2]f32 = .{ 0, 0 },
    held: u32 = 0,
    prev: f32 = -1,

    fn step(s: *Script, t: *ui.Tester, d: *Director, now: f32) void {
        d.now = now;
        if (s.held > 0) {
            s.held -= 1;
            if (s.held == 0) t.ctx.pointerUp();
        }
        events(d, now, s.prev);
        s.prev = now;
        d.cursor_alpha = 0;
        for (shown) |w| {
            const v = @min(clamp01((now - w[0]) / 0.3), clamp01((w[1] - now) / 0.3));
            d.cursor_alpha = @max(d.cursor_alpha, v);
        }
        while (s.next < moves.len) {
            const m = moves[s.next];
            if (now < m.at) break;
            if (s.started != s.next) {
                s.started = s.next;
                s.start = d.cursor;
                s.to = resolve(t, m.to) orelse d.cursor;
            }
            const p = clamp01((now - m.at) / m.dur);
            const e = p * p * (3 - 2 * p);
            d.cursor = .{ s.start[0] + (s.to[0] - s.start[0]) * e, s.start[1] + (s.to[1] - s.start[1]) * e };
            if (p < 1) break;
            if (m.act != .none) {
                t.ctx.input.mouse = .{ .x = d.cursor[0], .y = d.cursor[1] };
                t.ctx.updateHot();
                t.ctx.input.click_count = 1;
                t.ctx.pointerDown();
                s.held = 4;
                switch (m.act) {
                    .buy => d.order_open = true,
                    .place => d.placing = true,
                    .dismiss => d.alert = false,
                    else => {},
                }
            }
            s.next += 1;
        }
        t.ctx.input.mouse = if (d.cursor_alpha > 0) .{ .x = d.cursor[0], .y = d.cursor[1] } else .{ .x = -100, .y = -100 };
        t.ctx.updateHot();
    }
};

fn clamp01(v: f32) f32 {
    return std.math.clamp(v, 0, 1);
}

fn resolve(t: *ui.Tester, to: Target) ?[2]f32 {
    switch (to) {
        .point => |p| return p,
        .text => |s| {
            const r = t.findText(s) orelse {
                std.debug.print("reel: no \"{s}\" on screen\n", .{s});
                return null;
            };
            return .{ r.x + r.w / 2, r.y + r.h / 2 };
        },
        .beside => |b| {
            const r = t.findText(b.text) orelse {
                std.debug.print("reel: no \"{s}\" on screen\n", .{b.text});
                return null;
            };
            return .{ r.x + r.w / 2 + b.dx, r.y + r.h / 2 };
        },
    }
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    var stills: std.ArrayList(struct { frame: usize, path: []const u8 }) = .empty;
    defer stills.deinit(gpa);
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var dark = false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--cues")) return cues(io);
        if (std.mem.eql(u8, arg, "--dark")) {
            dark = true;
            continue;
        }
        const prefix = "--still=";
        if (!std.mem.startsWith(u8, arg, prefix)) return error.UnknownArgument;
        const v = arg[prefix.len..];
        const colon = std.mem.indexOfScalar(u8, v, ':') orelse return error.BadStill;
        const secs = try std.fmt.parseFloat(f32, v[0..colon]);
        try stills.append(gpa, .{ .frame = @intFromFloat(@round(secs * fps)), .path = v[colon + 1 ..] });
    }
    var d: Director = .{ .dark = dark, .market = .init(), .toaster = .{ .gpa = gpa, .width = 340, .corner = .top_right } };
    defer d.toaster.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(&d, Director.draw), .{ .width = scenes.width, .height = scenes.height, .scale = scale, .theme = @import("theme.zig").ui_(dark) });
    defer t.deinit();
    t.dt = 1.0 / @as(f32, fps);
    t.time = 0;
    var last: usize = @intFromFloat(at.done * fps);
    if (stills.items.len > 0) {
        last = 0;
        for (stills.items) |s| last = @max(last, s.frame + 1);
    }
    var script: Script = .{};
    const out = std.Io.File.stdout();
    for (0..last) |i| {
        script.step(&t, &d, @as(f32, @floatFromInt(i)) / fps);
        t.frame();
        if (stills.items.len > 0) {
            for (stills.items) |s| if (s.frame == i) try t.screenshot(s.path);
            continue;
        }
        const pixels = try t.render(gpa);
        defer pixels.deinit(gpa);
        try out.writeStreamingAll(io, pixels.bytes);
    }
}
