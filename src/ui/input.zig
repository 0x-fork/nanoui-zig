//! What one event brings, and what text editing keeps: keys, key
//! combinations offered to the view, text operations (typing, the input
//! method, selection, clipboard), the focused field as the input method
//! asks about it, where copied text goes, a field's editing state, and the
//! pointer and keys of this event.
const std = @import("std");
const types = @import("types.zig");

pub const Key = enum { backspace, delete, left, right, up, down, home, end, enter, tab, escape, page_up, page_down, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12 };

/// A key with modifiers, offered to the view before text editing sees it:
/// characters lowercase, other keys as `Shortcut.up` and the like.
pub const Shortcut = struct {
    key: u21,
    cmd: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,

    pub const up: u21 = 0xF700;
    pub const down: u21 = 0xF701;
    pub const left: u21 = 0xF702;
    pub const right: u21 = 0xF703;
    pub const escape: u21 = 0x1b;
    pub const tab: u21 = '\t';
    pub const enter: u21 = '\r';

    /// As this platform has it: Command is Control off macOS.
    pub fn native(s: Shortcut) Shortcut {
        if (@import("builtin").os.tag == .macos or !s.cmd) return s;
        var n = s;
        n.cmd = false;
        n.ctrl = true;
        return n;
    }
};

/// What text input does to the focused text, in AppKit's terms: typed or
/// pasted text, an input method's composition, and editing commands.
pub const TextOp = union(enum) {
    insert: []const u8,
    /// Text being composed (underlined), with the selection inside it.
    set_marked: struct { text: []const u8, sel_start: usize, sel_len: usize },
    unmark,
    command: Command,
};

pub const Command = enum {
    delete_backward,
    delete_forward,
    delete_word_backward,
    delete_to_line_start,
    move_left,
    move_right,
    move_word_left,
    move_word_right,
    move_line_start,
    move_line_end,
    select_left,
    select_right,
    select_word_left,
    select_word_right,
    select_line_start,
    select_line_end,
    select_all,
    insert_newline,
    insert_tab,
    cancel,
    copy,
    cut,
};

/// The focused text field as the last frame left it, for the input
/// method's questions between frames. Offsets are bytes.
pub const FocusedText = struct {
    id: u64,
    text: []const u8,
    caret: usize,
    anchor: usize,
    marked: ?[2]usize,
    /// Where the caret is drawn, in view points.
    caret_rect: types.Rect,
};

/// Where copied text goes: the system's clipboard, or the Tester's own.
pub const Clipboard = struct {
    ctx: ?*anyopaque = null,
    write: *const fn (ctx: ?*anyopaque, text: []const u8) void = systemWrite,

    fn systemWrite(_: ?*anyopaque, s: []const u8) void {
        @import("../platform.zig").clipboardWrite(s);
    }
};

/// A text field's editing state, kept across frames.
pub const EditState = struct {
    caret: usize = 0,
    anchor: usize = 0,
    marked: ?[2]usize = null,
    scroll_x: f32 = 0,
    /// Pressed in the field: dragging extends the selection.
    selecting: bool = false,
};

pub const Input = struct {
    mouse: types.Point = .{ .x = -1e6, .y = -1e6 },
    down: bool = false,
    /// The button went down / up in this event.
    pressed: bool = false,
    released: bool = false,
    click_count: u32 = 0,
    scroll: types.Point = .{},
    key: ?Key = null,
    /// Text typed or pasted in this event.
    chars: []const u8 = "",
    /// Text input operations of this event, for the focused text field.
    ops: []const TextOp = &.{},
    /// A key combination offered in this event (`Context.shortcut`).
    shortcut: ?Shortcut = null,
    shift: bool = false,
    cmd: bool = false,
    ctrl: bool = false,

    /// The key that adds to a selection with a click: Command on the
    /// Mac, Control elsewhere.
    pub fn adding(i: Input) bool {
        return if (comptime @import("builtin").os.tag == .macos) i.cmd else i.ctrl;
    }

    pub fn clearEdges(i: *Input) void {
        i.pressed = false;
        i.released = false;
        i.scroll = .{};
        i.key = null;
        i.chars = "";
        i.ops = &.{};
        i.shortcut = null;
    }
};
