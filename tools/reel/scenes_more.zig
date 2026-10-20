//! The reel's later scenes: Liquid Glass in motion, keyframes and
//! numbers, the code beside what it does, and the end card.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const motion = ui.motion;
const scenes = @import("scenes.zig");
const Director = scenes.Director;
const caption = scenes.caption;
const palette = @import("theme.zig");

pub fn glass(c: *ui.Context, d: *Director) void {
    const th = c.theme;
    // Cards drifting up under the glass, all scene long.
    const t = d.now - scenes.at.glass;
    const drift = 40 - t * 60;
    const hues = palette.hues(d.dark);
    const labels = [_][]const u8{ "Photos", "Albums", "Search" };
    {
        const area = ui.div(c).absolute().offset(150, 0).w(980).h(scenes.height).clip();
        defer area.end();
        for (0..14) |i| {
            const y = drift + @as(f32, @floatFromInt(i)) * 92 + 120;
            const card = ui.div(c).absolute().offset(0, y).w(980).h(76).row().px(26).gap(14).itemsCenter().rounded(20).bg(hues[(i + d.tab * 2) % hues.len]);
            defer card.end();
            ui.icon(c, "photo", .{ .size = 22, .color = .white });
            ui.text(c, c.print("{s} under the glass · {d}", .{ labels[d.tab], i + 1 }), .{ .size = 20, .weight = .semibold, .color = .white });
        }
    }
    // The glass toolbar springs in over them.
    const f = motion.frame(c, .{ .initial = .{ .y = -40, .opacity = 0, .scale = 0.95 }, .delay = 0.2, .transition = .{ .spring = motion.Spring.bouncy } });
    const bar = ui.div(c).absolute().offset(190, 40).w(900).h(76).row().itemsCenter().gap(12).px(14).rounded(38).glass(.{}).motion(f);
    {
        defer bar.end();
        _ = kit.tabs(c, &labels, &d.tab, .{ .variant = .glass, .size = .lg });
        ui.spacer(c);
        _ = kit.iconButton(c, "ellipsis", .{ .glass = true, .pill = true, .size = .lg });
        _ = kit.button(c, "Tap", .{ .glass = true, .variant = .primary, .pill = true, .size = .lg });
    }
    // A pane of clear glass, floating.
    const float = motion.keyframes(c, .{ .values = &.{ .{ .y = 0 }, .{ .y = -14 }, .{ .y = 0 } }, .duration = 2.4, .repeat = null });
    const pane = ui.div(c).absolute().offset(880, 380).w(180).h(180).rounded(46).glass(.{ .style = .clear }).center().motion(float);
    defer pane.end();
    ui.text(c, "Clear", .{ .size = 22, .weight = .semibold, .color = .white });
    _ = th;
}

pub fn loops(c: *ui.Context, d: *Director) void {
    const th = c.theme;
    caption(c, "keyframes · number", "Keyframes and numbers", "Loops, pulses and counters, drawn only while they move.");
    const row = ui.div(c).absolute().offset(72, 300).w(1136).row().gap(28).itemsCenter();
    defer row.end();
    // A counter counting up.
    {
        const card = ui.div(c).column().w(360).h(240).p(28).gap(6).rounded(24).bg(th.surface).border(th.border).shadow(.{ .color = th.shadow.alpha(0.5), .blur = 20, .y = 8 });
        defer card.end();
        ui.text(c, "Frames drawn", .{ .size = 16, .color = th.muted });
        const shown = motion.number(c, "count", d.count, .{ .tween = .{ .duration = 2.2, .ease = .ease_out } });
        ui.text(c, c.print("{d:.0}", .{shown}), .{ .size = 64, .weight = .bold, .mono = true });
        const live = ui.div(c).row().gap(10).itemsCenter();
        defer live.end();
        const pulse = motion.keyframes(c, .{ .values = &.{ .{ .scale = 1, .opacity = 1 }, .{ .scale = 1.7, .opacity = 0.3 }, .{ .scale = 1, .opacity = 1 } }, .duration = 1.2, .repeat = null });
        const dot = ui.div(c).w(12).h(12).roundedFull().bg(th.danger).motion(pulse);
        dot.end();
        ui.text(c, "live", .{ .size = 15, .color = th.muted });
    }
    // A ring filling with the counter.
    {
        const card = ui.div(c).column().w(240).h(240).center().gap(10).rounded(24).bg(th.surface).border(th.border).shadow(.{ .color = th.shadow.alpha(0.5), .blur = 20, .y = 8 });
        defer card.end();
        kit.ring(c, @min(1, motion.number(c, "ring", d.count / 12840, .{ .tween = .{ .duration = 2.2, .ease = .ease_out } })), .{ .size = 130 });
        ui.text(c, "Progress", .{ .size = 15, .color = th.muted });
    }
    // Loaders: a spinner, a bar running, skeletons breathing.
    {
        const card = ui.div(c).column().w(480).h(240).p(28).gap(18).rounded(24).bg(th.surface).border(th.border).shadow(.{ .color = th.shadow.alpha(0.5), .blur = 20, .y = 8 });
        defer card.end();
        {
            const r = ui.div(c).row().gap(14).itemsCenter();
            defer r.end();
            kit.spinner(c, .{ .size = 26, .color = th.accent });
            ui.text(c, "Loading…", .{ .size = 18, .weight = .medium });
        }
        kit.progress(c, null, .{ .height = 8 });
        const r2 = ui.div(c).row().wFull().gap(14).itemsCenter();
        defer r2.end();
        kit.skeleton(c, .{ .height = 52, .circle = true });
        const lines = ui.div(c).column().grow().gap(10);
        defer lines.end();
        kit.skeleton(c, .{ .height = 14 });
        kit.skeleton(c, .{ .height = 14, .width = .{ .px = 180 } });
    }
}

const snippet =
    \\const f = ui.motion.frame(c, .{
    \\    .target = .{ .width = if (open) 320 else 180 },
    \\    .initial = .{ .y = 12, .opacity = 0 },
    \\    .press = .{ .scale = 0.96 },
    \\    .transition = .{ .spring = .bouncy },
    \\});
    \\const card = ui.div(c).control().motion(f);
    \\if (card.clicked()) open = !open;
;

pub fn code(c: *ui.Context, d: *Director) void {
    const th = c.theme;
    caption(c, "zig", "A target, every frame", "No objects to keep. State lives by box, frames only while something moves.");
    {
        const card = ui.div(c).absolute().offset(72, 270).w(640).column().p(28).gap(4).rounded(20).bg(if (d.dark) th.surface else .hex(0x16140f));
        defer card.end();
        var lines = std.mem.splitScalar(u8, snippet, '\n');
        var i: usize = 0;
        while (lines.next()) |l| : (i += 1) {
            ui.key(c, c.print("code-{d}", .{i}));
            const f = motion.frame(c, .{ .initial = .{ .x = -12, .opacity = 0 }, .delay = 0.15 + motion.stagger(i, 0.06), .transition = .{ .spring = motion.Spring.snappy } });
            const line = ui.div(c).motion(f);
            defer line.end();
            ui.text(c, l, .{ .size = 17, .mono = true, .color = if (std.mem.indexOf(u8, l, "motion") != null) .hex(0xe8a33d) else .hex(0xedeae2) });
        }
    }
    // What it does, beside it, on a loop.
    const open = @mod(d.now - scenes.at.code, 1.3) < 0.65;
    const area = ui.div(c).absolute().offset(760, 270).w(450).h(300).center();
    defer area.end();
    const f = motion.frame(c, .{ .target = .{ .width = if (open) 320 else 180, .height = if (open) 180 else 110, .background = if (open) th.accent else th.surface }, .transition = .{ .spring = motion.Spring.bouncy } });
    const card = ui.div(c).column().p(20).rounded(22).border(th.border).shadow(.{ .color = th.shadow.alpha(0.7), .blur = 24, .y = 10 }).clip().motion(f);
    defer card.end();
    ui.text(c, if (open) "open" else "closed", .{ .size = 22, .weight = .bold, .mono = true, .color = if (open) th.accent_text else th.text });
}

pub fn end(c: *ui.Context, d: *Director) void {
    const th = c.theme;
    _ = d;
    const box = ui.div(c).sizeFull().column().center().gap(16);
    defer box.end();
    const f = motion.frame(c, .{ .initial = .{ .scale = 0.8, .opacity = 0 }, .transition = .{ .spring = motion.Spring.bouncy } });
    {
        const n = ui.div(c).motion(f);
        defer n.end();
        ui.text(c, "nanoui", .{ .size = 104, .weight = .bold });
    }
    const items = [_][]const u8{ "ui.motion", "nanoui.kit", "Liquid Glass" };
    {
        const r = ui.div(c).row().gap(12);
        defer r.end();
        for (items, 0..) |it, i| {
            ui.key(c, it);
            const g = motion.frame(c, .{ .initial = .{ .y = 14, .opacity = 0 }, .delay = 0.35 + motion.stagger(i, 0.1), .transition = .{ .spring = motion.Spring.snappy } });
            const chip = ui.div(c).px(18).py(9).roundedFull().bg(th.accent.alpha(0.12)).motion(g);
            defer chip.end();
            ui.text(c, it, .{ .size = 20, .weight = .semibold, .mono = true, .color = th.accent });
        }
    }
    const l = motion.frame(c, .{ .initial = .{ .opacity = 0 }, .delay = 0.8, .transition = .{ .tween = .{ .duration = 0.5 } } });
    const link = ui.div(c).motion(l);
    defer link.end();
    ui.text(c, "github.com/justrach/nanoui", .{ .size = 20, .color = th.muted, .mono = true });
}
