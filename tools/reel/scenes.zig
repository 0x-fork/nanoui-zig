//! The reel's scenes: what each draws at its time, and when each comes
//! and goes. Every scene enters and leaves with `ui.motion` presence (the
//! next comes in as the last goes), and everything in them moves by
//! `ui.motion` and `nanoui.kit` as an app's would: springs, presence,
//! stagger, layout, glass, keyframes, numbers.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const motion = ui.motion;
const more = @import("scenes_more.zig");
const palette = @import("theme.zig");

/// Points; drawn at 1.5× for 1920 × 1080.
pub const width = 1280;
pub const height = 720;

/// When each scene starts, and when the reel ends.
pub const at = struct {
    pub const title = 0.0;
    pub const spring = 3.0;
    pub const presence = 8.0;
    pub const layout = 12.5;
    pub const glass = 17.0;
    pub const loops = 21.5;
    pub const code = 25.0;
    pub const end = 28.0;
    pub const done = 30.0;
};

pub const Scene = enum { title, spring, presence, layout, glass, loops, code, end };

pub fn sceneAt(t: f32) Scene {
    if (t < at.spring) return .title;
    if (t < at.presence) return .spring;
    if (t < at.layout) return .presence;
    if (t < at.glass) return .layout;
    if (t < at.loops) return .glass;
    if (t < at.code) return .loops;
    if (t < at.end) return .code;
    return .end;
}

pub const Director = struct {
    now: f32 = 0,
    dark: bool = false,
    /// What the script changes: the card, the dialog, the list's order,
    /// the glass tab, the counter.
    open: bool = false,
    dialog: bool = false,
    order: [6]u8 = .{ 0, 1, 2, 3, 4, 5 },
    tab: usize = 0,
    count: f32 = 0,
    toaster: kit.Toaster,
    /// The pointer, as a person moves it, and when it last pressed.
    cursor: [2]f32 = .{ 1100, 640 },
    cursor_alpha: f32 = 0,

    pub fn view(d: *Director, c: *ui.Context) void {
        const th = c.theme;
        const root = ui.div(c).sizeFull().bg(th.background);
        defer root.end();
        // A soft wash of the accent in a corner, behind everything.
        const wash = ui.div(c).absolute().offset(-200, -260).w(900).h(900).roundedFull().bg(th.accent.alpha(if (d.dark) 0.10 else 0.06));
        wash.end();
        const now = sceneAt(d.now);
        inline for (comptime std.enums.values(Scene)) |s| {
            if (motion.present(c, @tagName(s), now == s, .{
                .initial = .{ .y = 40, .opacity = 0, .scale = 0.98 },
                .exit = .{ .y = -30, .opacity = 0, .scale = 0.98 },
                .transition = .{ .spring = .{ .stiffness = 170, .damping = 24 } },
            })) |f| {
                const stage = ui.div(c).absolute().w(width).h(height).motion(f);
                defer stage.end();
                switch (s) {
                    .title => title(c, d),
                    .spring => spring(c, d),
                    .presence => presence(c, d),
                    .layout => layout(c, d),
                    .glass => more.glass(c, d),
                    .loops => more.loops(c, d),
                    .code => more.code(c, d),
                    .end => more.end(c, d),
                }
            }
        }
        d.toaster.view(c);
        cursor(c, d);
    }
};

/// The scene's caption at the top left: a small label, a title, a line.
pub fn caption(c: *ui.Context, label: []const u8, head: []const u8, line: []const u8) void {
    const th = c.theme;
    const box = ui.div(c).absolute().offset(72, 60).column().gap(8);
    defer box.end();
    ui.text(c, label, .{ .size = 13, .weight = .semibold, .mono = true, .color = th.accent });
    ui.text(c, head, .{ .size = 40, .weight = .bold });
    ui.text(c, line, .{ .size = 17, .color = th.muted });
}

fn title(c: *ui.Context, d: *Director) void {
    const th = c.theme;
    _ = d;
    const box = ui.div(c).sizeFull().column().center().gap(18);
    defer box.end();
    {
        const r = ui.div(c).row().itemsEnd();
        defer r.end();
        const word = "ui.motion";
        for (word, 0..) |ch, i| {
            ui.key(c, c.print("l{d}", .{i}));
            const f = motion.frame(c, .{ .initial = .{ .y = 60, .opacity = 0, .scale = 0.6 }, .delay = 0.25 + motion.stagger(i, 0.05), .transition = .{ .spring = motion.Spring.bouncy } });
            const l = ui.div(c).motion(f);
            defer l.end();
            ui.text(c, c.print("{c}", .{ch}), .{ .size = 120, .weight = .bold, .mono = i < 3, .color = if (i < 3) th.accent else th.text });
        }
    }
    const sub = motion.frame(c, .{ .initial = .{ .y = 16, .opacity = 0 }, .delay = 1.0, .transition = .{ .spring = motion.Spring.gentle } });
    const s = ui.div(c).column().itemsCenter().gap(10).motion(sub);
    defer s.end();
    ui.text(c, "Declarative, interruptible motion for nanoui", .{ .size = 26, .weight = .medium });
    ui.text(c, "Springs · presence · layout · glass · in Zig", .{ .size = 18, .color = th.muted, .mono = true });
}

fn spring(c: *ui.Context, d: *Director) void {
    const th = c.theme;
    caption(c, "motion.frame", "Springs", "Change the target midway: it turns from where it is, keeping its speed.");
    const box = ui.div(c).sizeFull().center().pt(90);
    defer box.end();
    const f = motion.frame(c, .{
        .target = .{ .width = if (d.open) 620 else 300, .height = if (d.open) 300 else 170, .radius = if (d.open) 40 else 22, .background = if (d.open) th.accent else th.surface },
        .press = .{ .scale = 0.95 },
        .transition = .{ .spring = motion.Spring.bouncy },
    });
    const card = ui.div(c).column().p(28).gap(8).border(th.border).shadow(.{ .color = th.shadow.alpha(0.8), .blur = 30, .y = 12 }).clip().control().motion(f);
    defer card.end();
    if (card.clicked()) d.open = !d.open;
    const fg = if (d.open) th.accent_text else th.text;
    ui.text(c, if (d.open) "Open" else "Click me", .{ .size = 30, .weight = .bold, .color = fg });
    ui.text(c, "size · corners · color", .{ .size = 16, .color = if (d.open) th.accent_text.alpha(0.8) else th.muted, .mono = true });
}

fn presence(c: *ui.Context, d: *Director) void {
    caption(c, "motion.present", "Presence", "Boxes come in, and stay drawn while they leave.");
    const box = ui.div(c).sizeFull().center().pt(60);
    defer box.end();
    {
        const r = ui.div(c).row().gap(12);
        defer r.end();
        _ = kit.button(c, "Save", .{ .variant = .primary, .size = .lg, .icon = "checkmark" });
        _ = kit.button(c, "Delete project…", .{ .variant = .danger, .size = .lg, .icon = "trash" });
    }
    if (kit.dialog(c, "reel-dialog", &d.dialog, .{ .title = "Delete project?", .description = "Its files and history go too. This can't be undone.", .ok = "Delete", .ok_variant = .danger })) |dl| {
        _ = kit.alert(c, .{ .status = .warning, .title = "3 people use it", .description = "They'll lose access at once." });
        _ = dl.end();
    }
}

fn layout(c: *ui.Context, d: *Director) void {
    const th = c.theme;
    caption(c, "stagger · layout", "Stagger and layout", "Items come in one after another, and glide when the layout moves them.");
    const box = ui.div(c).absolute().offset(400, 250).w(480).column().gap(10);
    defer box.end();
    const names = [_][]const u8{ "Springs keep their speed", "Tweens ease from where they are", "Presence waits for exits", "Layout glides to the new place", "Keyframes loop and yoyo", "Numbers count up" };
    const hues = palette.hues(d.dark);
    for (d.order, 0..) |n, i| {
        ui.key(c, c.print("row-{d}", .{n}));
        const f = motion.frame(c, .{ .initial = .{ .x = -40, .opacity = 0 }, .delay = 0.3 + motion.stagger(i, 0.08), .layout = true, .transition = .{ .spring = .{ .stiffness = 260, .damping = 24 } } });
        const row = ui.div(c).row().wFull().h(56).px(20).gap(14).itemsCenter().rounded(14).bg(th.surface).border(th.border).shadow(.{ .color = th.shadow.alpha(0.4), .blur = 8, .y = 3 }).motion(f);
        defer row.end();
        _ = c.leaf(.{ .width = .{ .px = 12 }, .height = .{ .px = 12 }, .radius = 6, .background = hues[n] }, .none, null);
        ui.text(c, names[n], .{ .size = 18, .weight = .medium });
    }
}

/// The pointer: an arrow with a shadow, wherever the script has it.
fn cursor(c: *ui.Context, d: *Director) void {
    if (d.cursor_alpha <= 0.01) return;
    const p = ui.div(c).fixed().offset(d.cursor[0] - 4, d.cursor[1] - 3).layer(90).opacity(d.cursor_alpha);
    defer p.end();
    ui.icon(c, "cursorarrow", .{ .size = 30, .weight = .regular, .color = c.theme.text });
}
