//! The reel: nanotrade, a mock trading app that nanoui draws, used for 30
//! seconds as a person would. Every motion in it is `ui.motion` or
//! `nanoui.kit` doing an app's work: the window springs in, prices ease
//! to each tick, the chart's candles morph between ranges, a crosshair
//! chases the pointer, an order panel slides in, a toast reports the fill,
//! the watchlist glides into a new order, an alert pops. A caption at the
//! bottom names the motion at work. Then the end card.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const motion = ui.motion;
const trade = @import("trade.zig");
const view = @import("trade_view.zig");

/// Points; drawn at 1.5× for 1920 × 1080.
pub const width = 1280;
pub const height = 720;

/// When each part begins.
pub const at = struct {
    pub const open = 0.0;
    pub const ticks = 2.0;
    pub const ranges = 6.5;
    pub const hover = 10.5;
    pub const order = 15.5;
    pub const sort = 21.5;
    pub const alert = 25.5;
    pub const end = 27.6;
    pub const done = 30.0;
};

/// What the caption says, and from when.
const captions = [_]struct { f32, []const u8, []const u8 }{
    .{ 0.7, "ui.motion", "nanotrade, a mock app nanoui draws, every motion its own" },
    .{ at.ticks + 0.2, "motion.number", "prices ease to each tick and flash their direction" },
    .{ at.ranges + 0.3, "motion.frame", "candles keep their place and spring to the new range" },
    .{ at.hover + 0.3, "spring targets", "the crosshair and readout chase the pointer" },
    .{ at.order + 0.3, "motion.present", "the order panel slides in; the fill arrives as a toast" },
    .{ at.sort + 0.3, "layout", "re-sorted rows glide to their new place" },
    .{ at.alert + 0.1, "nanoui.kit", "a dialog springs in and dims what's behind it" },
};

pub const Director = struct {
    now: f32 = 0,
    dark: bool = false,
    market: trade.Market,
    range: usize = 0,
    /// The watchlist sorted by change, the crosshair shown.
    sorted: bool = false,
    crosshair: bool = false,
    /// The order: open, its shares, placing, filled at `entry`.
    order_open: bool = false,
    qty: f64 = 10,
    placing: bool = false,
    filled: bool = false,
    entry: f32 = 0,
    alert: bool = false,
    receding: bool = false,
    /// The last tick: when, and which way.
    tick_at: f32 = -10,
    last_up: bool = true,
    toaster: kit.Toaster,
    cursor: [2]f32 = .{ 1100, 640 },
    cursor_alpha: f32 = 0,

    pub fn draw(d: *Director, c: *ui.Context) void {
        const th = c.theme;
        const root = ui.div(c).sizeFull().bg(th.background.mix(th.text, if (d.dark) 0.04 else 0.03));
        defer root.end();
        const wash = ui.div(c).absolute().offset(-260, -300).w(1000).h(1000).roundedFull().bg(th.accent.alpha(if (d.dark) 0.08 else 0.07));
        wash.end();
        view.window(c, d);
        caption(c, d);
        if (kit.dialog(c, "alert", &d.alert, .{ .title = "Price alert: NVDA crossed 186", .description = "Your alert at 186.00 triggered. NVDA is up on the day.", .ok = "View chart", .cancel = "Dismiss", .width = 420 })) |dl| {
            _ = kit.alert(c, .{ .status = .success, .title = "Position up", .description = "Your 40 shares are in profit." });
            _ = dl.end();
        }
        d.toaster.view(c);
        endCard(c, d);
        cursor(c, d);
    }
};

/// The caption pill at the bottom: the motion at work, and what it does.
fn caption(c: *ui.Context, d: *Director) void {
    const th = c.theme;
    var which: ?usize = null;
    for (captions, 0..) |cap, i| if (d.now >= cap[0]) {
        which = i;
    };
    if (d.now >= at.end) which = null;
    for (captions, 0..) |cap, i| {
        const f = motion.present(c, c.print("cap-{d}", .{i}), which == i, .{
            .initial = .{ .y = 16, .opacity = 0 },
            .exit = .{ .y = -8, .opacity = 0 },
            .transition = .{ .spring = motion.Spring.snappy },
        }) orelse continue;
        const pill = ui.div(c).fixed().offset(width / 2 - 330, height - 30).w(660).h(26).row().center().gap(10).layer(60).motion(f);
        defer pill.end();
        const tag = ui.div(c).px(8).py(2).rounded(6).bg(th.accent);
        {
            defer tag.end();
            ui.text(c, cap[1], .{ .size = 12, .weight = .bold, .mono = true, .color = th.accent_text });
        }
        ui.text(c, cap[2], .{ .size = 14, .weight = .medium, .color = th.text });
    }
}

fn endCard(c: *ui.Context, d: *Director) void {
    const th = c.theme;
    const f = motion.present(c, "end", d.now >= at.end, .{ .initial = .{ .scale = 0.9, .opacity = 0 }, .exit = .{ .opacity = 0 }, .transition = .{ .spring = motion.Spring.bouncy } }) orelse return;
    // Over the app, which steps back behind a veil of the page's color.
    const box = ui.div(c).fixed().w(width).h(height).column().center().gap(16).layer(70).bg(th.background.alpha(0.86)).motion(f);
    defer box.end();
    ui.text(c, "nanoui", .{ .size = 104, .weight = .bold });
    {
        const r = ui.div(c).row().gap(12);
        defer r.end();
        for ([_][]const u8{ "ui.motion", "nanoui.kit", "Liquid Glass" }, 0..) |it, i| {
            ui.key(c, it);
            const g = motion.frame(c, .{ .initial = .{ .y = 14, .opacity = 0 }, .delay = 0.3 + motion.stagger(i, 0.1), .transition = .{ .spring = motion.Spring.snappy } });
            const chip = ui.div(c).px(18).py(9).roundedFull().bg(th.accent.alpha(0.14)).motion(g);
            defer chip.end();
            ui.text(c, it, .{ .size = 20, .weight = .semibold, .mono = true, .color = th.accent });
        }
    }
    const l = motion.frame(c, .{ .initial = .{ .opacity = 0 }, .delay = 0.7, .transition = .{ .tween = .{ .duration = 0.5 } } });
    const link = ui.div(c).motion(l);
    defer link.end();
    ui.text(c, "Native apps in Zig · github.com/justrach/nanoui", .{ .size = 20, .color = th.muted, .mono = true });
}

/// The pointer: an arrow, wherever the script has it.
fn cursor(c: *ui.Context, d: *Director) void {
    if (d.cursor_alpha <= 0.01) return;
    const p = ui.div(c).fixed().offset(d.cursor[0] - 4, d.cursor[1] - 3).layer(90).opacity(d.cursor_alpha);
    defer p.end();
    ui.icon(c, "cursorarrow", .{ .size = 30, .weight = .regular, .color = c.theme.text });
}
