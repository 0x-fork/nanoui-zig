//! A 30-second reel of `ui.motion`, drawn by nanoui: the scenes
//! (scenes.zig) run in a Tester, offscreen, 30 frames a second, and each
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

const Target = union(enum) { point: [2]f32, text: []const u8 };

const Move = struct { at: f32, dur: f32, to: Target, click: bool = false };

const moves = [_]Move{
    .{ .at = at.spring + 0.7, .dur = 0.7, .to = .{ .text = "Click me" }, .click = true },
    .{ .at = at.spring + 1.75, .dur = 0.2, .to = .{ .point = .{ 640, 420 } }, .click = true },
    .{ .at = at.spring + 2.75, .dur = 0.25, .to = .{ .point = .{ 640, 425 } }, .click = true },
    .{ .at = at.spring + 4.0, .dur = 0.6, .to = .{ .point = .{ 1080, 640 } } },
    .{ .at = at.presence + 1.8, .dur = 0.7, .to = .{ .text = "Delete project…" }, .click = true },
    .{ .at = at.presence + 3.4, .dur = 0.6, .to = .{ .text = "Cancel" }, .click = true },
    .{ .at = at.glass + 1.0, .dur = 0.6, .to = .{ .text = "Albums" }, .click = true },
    .{ .at = at.glass + 2.0, .dur = 0.4, .to = .{ .text = "Search" }, .click = true },
    .{ .at = at.glass + 3.0, .dur = 0.5, .to = .{ .text = "Tap" }, .click = true },
};

/// When the pointer shows.
const shown = [_][2]f32{ .{ at.spring + 0.4, at.spring + 4.7 }, .{ at.presence + 1.5, at.presence + 4.2 }, .{ at.glass + 0.7, at.glass + 4.0 } };

/// What the script changes without a click, and when.
fn events(d: *Director, now: f32, prev: f32) void {
    const crossed = struct {
        fn f(p: f32, n: f32, t: f32) bool {
            return p < t and n >= t;
        }
    }.f;
    if (crossed(prev, now, at.presence + 0.5)) d.toaster.push(.{ .status = .success, .title = "Saved", .message = "Your changes are in.", .duration = 2.2 });
    if (crossed(prev, now, at.presence + 1.0)) d.toaster.push(.{ .status = .info, .title = "Synced", .message = "Up to date on every device.", .duration = 2.2 });
    if (crossed(prev, now, at.presence + 1.5)) d.toaster.push(.{ .status = .warning, .title = "Low space", .message = "2 GB left on this disk.", .duration = 2.0 });
    if (crossed(prev, now, at.layout + 2.0)) d.order = .{ 3, 0, 5, 1, 4, 2 };
    if (crossed(prev, now, at.layout + 3.2)) d.order = .{ 5, 2, 0, 4, 3, 1 };
    if (crossed(prev, now, at.loops + 0.4)) d.count = 12840;
}

/// The times sounds go with: each click, and each cut to a scene.
fn cues(io: std.Io) !void {
    var buf: [4096]u8 = undefined;
    var w = std.Io.File.stdout().writer(io, &buf);
    const o = &w.interface;
    for (moves) |m| if (m.click) try o.print("click {d:.3}\n", .{m.at + m.dur});
    for ([_]f32{ at.presence + 0.5, at.presence + 1.0, at.presence + 1.5 }) |t| try o.print("chime {d:.3}\n", .{t});
    for ([_]f32{ at.spring, at.presence, at.layout, at.glass, at.loops, at.code, at.end }) |cut| try o.print("cut {d:.3}\n", .{cut});
    try o.flush();
}

const Script = struct {
    next: usize = 0,
    started: ?usize = null,
    start: [2]f32 = .{ 0, 0 },
    to: [2]f32 = .{ 0, 0 },
    /// Frames left with the button down.
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
            if (now >= w[0] and now < w[0] + 0.5 / @as(f32, fps)) d.cursor = .{ 1080, 640 };
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
            if (m.click) {
                t.ctx.input.mouse = .{ .x = d.cursor[0], .y = d.cursor[1] };
                t.ctx.updateHot();
                t.ctx.input.click_count = 1;
                t.ctx.pointerDown();
                // Held for a few frames, so the press shows.
                s.held = 4;
                if (m.to == .text and std.mem.eql(u8, m.to.text, "Delete project…")) d.dialog = true;
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
    var d: Director = .{ .dark = dark, .toaster = .{ .gpa = gpa, .width = 380 } };
    defer d.toaster.deinit();
    var t: ui.Tester = undefined;
    try t.init(gpa, .init(&d, Director.view), .{ .width = scenes.width, .height = scenes.height, .scale = scale, .theme = if (dark) ui.Theme.dark_theme else ui.Theme.light });
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
