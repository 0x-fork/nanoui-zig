//! Emacs's and Vim's keys for a text field (`textField`'s `keys`), for
//! those whose fingers know them.
//!
//! Emacs, as readline has it: ^A ^E to the line's ends, ^B ^F a character,
//! ⌥B ⌥F a word, ^D ^H delete, ^K ^U kill to the end and the start, ^W ⌥D
//! kill a word, ^Y yank back what was killed.
//!
//! Vim: the field starts in insert mode; Esc goes to normal mode, where
//! keys are commands: h l w b e 0 ^ $ move; x X delete; i a I A s S C
//! insert; d and c with w $ 0 or doubled (dd, cc); D; p P put back what
//! was deleted; j k step through history (the app's, through `Result`).
const std = @import("std");
const types = @import("types.zig");
const ctx_mod = @import("context.zig");
const tf = @import("textfield.zig");
const Context = ctx_mod.Context;
const EditState = ctx_mod.EditState;
const Command = @import("input.zig").Command;

pub const Keymap = enum { system, emacs, vim };

/// What the keymap used of this event: its text (not to be typed) and its
/// key (not to be handled as usual).
pub const Took = struct { text: bool = false, key: bool = false };

pub fn handle(c: *Context, b: *tf.TextBuffer, e: *EditState, opts: tf.Options, r: *tf.Result) Took {
    return switch (opts.keys) {
        .system => .{},
        .emacs => emacs(c, b, e, opts, r),
        .vim => vim(c, b, e, opts, r),
    };
}

fn run(c: *Context, b: *tf.TextBuffer, e: *EditState, opts: tf.Options, r: *tf.Result, cmd: Command) void {
    tf.apply(b, e, .{ .command = cmd }, opts, c.clipboard, r);
}

/// Takes the event's key combination, so neither the app nor the field
/// handles it again.
fn take(c: *Context) void {
    c.shortcut_taken = true;
    c.input.shortcut = null;
    c.changed = true;
}

/// Removes bytes [from, to), keeping them for yanking back.
fn kill(b: *tf.TextBuffer, e: *EditState, from: usize, to: usize, r: *tf.Result) void {
    if (to <= from) return;
    const s = b.text();
    const n = @min(to - from, e.killed.len);
    @memcpy(e.killed[0..n], s[from .. from + n]);
    e.killed_len = n;
    b.remove(from, to);
    e.caret = from;
    e.anchor = from;
    r.changed = true;
}

fn yank(b: *tf.TextBuffer, e: *EditState, at: usize, r: *tf.Result) void {
    if (e.killed_len == 0) return;
    const n = b.insert(at, e.killed[0..e.killed_len]);
    e.caret = at + n;
    e.anchor = e.caret;
    r.changed = true;
}

fn wordStart(s: []const u8, i: usize) usize {
    var j = i;
    while (j > 0 and !word(s[j - 1])) j -= 1;
    while (j > 0 and word(s[j - 1])) j -= 1;
    return j;
}

fn wordEnd(s: []const u8, i: usize) usize {
    var j = i;
    while (j < s.len and !word(s[j])) j += 1;
    while (j < s.len and word(s[j])) j += 1;
    return j;
}

/// Where the next word starts, as Vim's w goes: past this word (or run of
/// other characters), then past the spaces.
fn nextStart(s: []const u8, i: usize) usize {
    var j = i;
    if (j < s.len and word(s[j])) {
        while (j < s.len and word(s[j])) j += 1;
    } else while (j < s.len and !word(s[j]) and s[j] != ' ') j += 1;
    while (j < s.len and s[j] == ' ') j += 1;
    return j;
}

fn word(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_' or ch >= 0x80;
}

fn emacs(c: *Context, b: *tf.TextBuffer, e: *EditState, opts: tf.Options, r: *tf.Result) Took {
    const k = c.input.shortcut orelse return .{};
    if (k.cmd or k.shift or !(k.ctrl != k.alt)) return .{};
    const s = b.text();
    if (k.ctrl) switch (k.key) {
        'a' => run(c, b, e, opts, r, .move_line_start),
        'e' => run(c, b, e, opts, r, .move_line_end),
        'b' => run(c, b, e, opts, r, .move_left),
        'f' => run(c, b, e, opts, r, .move_right),
        'd' => run(c, b, e, opts, r, .delete_forward),
        'h' => run(c, b, e, opts, r, .delete_backward),
        'k' => kill(b, e, e.caret, s.len, r),
        'u' => kill(b, e, 0, e.caret, r),
        'w' => kill(b, e, wordStart(s, e.caret), e.caret, r),
        'y' => yank(b, e, e.caret, r),
        else => return .{},
    } else switch (k.key) {
        'b' => run(c, b, e, opts, r, .move_word_left),
        'f' => run(c, b, e, opts, r, .move_word_right),
        'd' => kill(b, e, e.caret, wordEnd(s, e.caret), r),
        else => return .{},
    }
    take(c);
    return .{ .key = true };
}

fn vim(c: *Context, b: *tf.TextBuffer, e: *EditState, opts: tf.Options, r: *tf.Result) Took {
    const esc = if (c.input.shortcut) |k| k.key == ctx_mod.Shortcut.escape and !k.cmd and !k.ctrl else c.input.key == .escape;
    if (!e.vim_normal) {
        if (!esc) return .{};
        // Insert → normal, the caret back onto the last character, as Vim does.
        e.vim_normal = true;
        e.vim_pending = 0;
        if (e.caret > 0 and e.caret == e.anchor) run(c, b, e, opts, r, .move_left);
        if (c.input.shortcut != null) take(c);
        c.changed = true;
        return .{ .key = true };
    }
    // Esc in normal mode is the app's (stop what runs), unless it
    // cancels an operator waiting for its motion.
    if (esc) {
        if (e.vim_pending == 0) return .{};
        e.vim_pending = 0;
        if (c.input.shortcut != null) take(c);
        return .{ .key = true };
    }
    // Normal mode: what is typed is commands.
    var typed: std.ArrayList(u8) = .empty;
    typed.appendSlice(c.alloc(), c.input.chars) catch {};
    for (c.input.ops) |op| if (op == .insert) typed.appendSlice(c.alloc(), op.insert) catch {};
    if (typed.items.len == 0) return .{};
    for (typed.items, 0..) |ch, i| {
        // A command that went to insert mode: the rest is typed.
        if (!e.vim_normal) {
            tf.apply(b, e, .{ .insert = typed.items[i..] }, opts, c.clipboard, r);
            break;
        }
        normal(c, b, e, opts, r, ch);
        // In normal mode the caret is on a character, never past the last.
        if (e.vim_normal and b.len > 0 and e.caret >= b.len) {
            e.caret = b.len - 1;
            e.anchor = e.caret;
        }
    }
    c.changed = true;
    return .{ .text = true };
}

fn normal(c: *Context, b: *tf.TextBuffer, e: *EditState, opts: tf.Options, r: *tf.Result, ch: u8) void {
    const s = b.text();
    // An operator waiting for its motion: d or c.
    if (e.vim_pending != 0) {
        const op = e.vim_pending;
        e.vim_pending = 0;
        const range: ?[2]usize = switch (ch) {
            'w' => .{ e.caret, nextStart(s, e.caret) },
            'e' => .{ e.caret, wordEnd(s, e.caret) },
            'b' => .{ wordStart(s, e.caret), e.caret },
            '$' => .{ e.caret, s.len },
            '0', '^' => .{ 0, e.caret },
            else => if (ch == op) .{ 0, s.len } else null,
        };
        if (range) |rg| kill(b, e, rg[0], rg[1], r);
        if (op == 'c' and range != null) e.vim_normal = false;
        return;
    }
    switch (ch) {
        'h' => run(c, b, e, opts, r, .move_left),
        'l' => if (e.caret + 1 < s.len) run(c, b, e, opts, r, .move_right),
        'w' => {
            e.caret = @min(nextStart(s, e.caret), s.len -| 1);
            e.anchor = e.caret;
        },
        'e' => {
            e.caret = wordEnd(s, @min(s.len, e.caret + 1)) -| 1;
            e.anchor = e.caret;
        },
        'b' => run(c, b, e, opts, r, .move_word_left),
        '0', '^' => run(c, b, e, opts, r, .move_line_start),
        '$' => {
            e.caret = s.len -| 1;
            e.anchor = e.caret;
        },
        'x' => if (e.caret < s.len) kill(b, e, e.caret, e.caret + 1, r),
        'X' => if (e.caret > 0) kill(b, e, e.caret - 1, e.caret, r),
        'D' => kill(b, e, e.caret, s.len, r),
        'C' => {
            kill(b, e, e.caret, s.len, r);
            e.vim_normal = false;
        },
        's' => {
            if (e.caret < s.len) kill(b, e, e.caret, e.caret + 1, r);
            e.vim_normal = false;
        },
        'S' => {
            kill(b, e, 0, s.len, r);
            e.vim_normal = false;
        },
        'd', 'c' => e.vim_pending = ch,
        'p' => yank(b, e, @min(s.len, e.caret + 1), r),
        'P' => yank(b, e, e.caret, r),
        'i' => e.vim_normal = false,
        'a' => {
            if (e.caret < s.len) run(c, b, e, opts, r, .move_right);
            e.vim_normal = false;
        },
        'I' => {
            run(c, b, e, opts, r, .move_line_start);
            e.vim_normal = false;
        },
        'A' => {
            run(c, b, e, opts, r, .move_line_end);
            e.vim_normal = false;
        },
        'k' => r.history = -1,
        'j' => r.history = 1,
        else => {},
    }
}
