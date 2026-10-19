//! Emacs's and Vim's keys in a text field, through the Tester.
const std = @import("std");
const testing = std.testing;
const ui = @import("ui.zig");

const Keys = struct {
    buf: ui.TextBuffer = .{},
    keys: ui.Keymap,
    last: ui.TextFieldResult = .{},
    history: i8 = 0,
    fn view(k: *@This(), c: *ui.Context) void {
        ui.column(c, .{ .padding = .all(10) });
        defer ui.end(c);
        c.focus = c.peekId(null);
        k.last = ui.textField(c, &k.buf, .{ .keys = k.keys });
        // Kept: the frame may be built again, without the key.
        if (k.last.history != 0) k.history = k.last.history;
    }
};

test "Emacs's keys in a text field: ends of the line, kill and yank, words" {
    var k: Keys = .{ .keys = .emacs };
    var t: ui.Tester = undefined;
    try t.init(testing.allocator, .init(&k, Keys.view), .{ .width = 400, .height = 100 });
    defer t.deinit();
    t.settle(1);
    t.typeText("hello brave world");
    try testing.expect(t.shortcut(.{ .key = 'w', .ctrl = true }));
    try testing.expectEqualStrings("hello brave ", k.buf.text());
    try testing.expect(t.shortcut(.{ .key = 'a', .ctrl = true }));
    try testing.expect(t.shortcut(.{ .key = 'f', .alt = true }));
    try testing.expect(t.shortcut(.{ .key = 'k', .ctrl = true }));
    try testing.expectEqualStrings("hello", k.buf.text());
    try testing.expect(t.shortcut(.{ .key = 'e', .ctrl = true }));
    try testing.expect(t.shortcut(.{ .key = 'y', .ctrl = true }));
    try testing.expectEqualStrings("hello brave ", k.buf.text());
    try testing.expect(t.shortcut(.{ .key = 'u', .ctrl = true }));
    try testing.expectEqualStrings("", k.buf.text());
    // The system's keys leave ^W to the app.
    var plain: Keys = .{ .keys = .system };
    var t2: ui.Tester = undefined;
    try t2.init(testing.allocator, .init(&plain, Keys.view), .{ .width = 400, .height = 100 });
    defer t2.deinit();
    t2.settle(1);
    t2.typeText("abc");
    try testing.expect(!t2.shortcut(.{ .key = 'w', .ctrl = true }));
    try testing.expectEqualStrings("abc", plain.buf.text());
}

test "Vim's keys in a text field: normal mode, motions, operators, put" {
    var k: Keys = .{ .keys = .vim };
    var t: ui.Tester = undefined;
    try t.init(testing.allocator, .init(&k, Keys.view), .{ .width = 400, .height = 100 });
    defer t.deinit();
    t.settle(1);
    t.typeText("git commit -m wip");
    try testing.expect(!k.last.vim_normal);
    try testing.expect(t.shortcut(.{ .key = ui.Shortcut.escape }));
    try testing.expect(k.last.vim_normal);
    // Typing is commands now: 0 to the start, dw deletes a word.
    t.typeText("0dw");
    try testing.expectEqualStrings("commit -m wip", k.buf.text());
    // $ to the end, x deletes under the caret, p puts it back after.
    t.typeText("$x");
    try testing.expectEqualStrings("commit -m wi", k.buf.text());
    t.typeText("P");
    try testing.expectEqualStrings("commit -m wpi", k.buf.text());
    // A appends in insert mode; Esc and cc changes the whole line.
    t.typeText("A!");
    try testing.expectEqualStrings("commit -m wpi!", k.buf.text());
    try testing.expect(t.shortcut(.{ .key = ui.Shortcut.escape }));
    t.typeText("ccnew");
    try testing.expectEqualStrings("new", k.buf.text());
    try testing.expect(!k.last.vim_normal);
    // j and k ask the app for history.
    try testing.expect(t.shortcut(.{ .key = ui.Shortcut.escape }));
    t.typeText("k");
    try testing.expectEqual(@as(i8, -1), k.history);
}
