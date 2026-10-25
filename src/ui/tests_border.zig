//! A faint border on an opaque rounded box, as a composer draws it: round
//! the corners no pixel may be lighter than the border laid over the fill.
//! Mixing the two straight made the anti-aliased pixels between them light
//! and nearly opaque, a bright rim on every curve.
const std = @import("std");
const testing = std.testing;
const ui = @import("ui.zig");

const fill: ui.Color = .{ .r = 0.14, .g = 0.13, .b = 0.10, .a = 1 };
const edge: ui.Color = .{ .r = 1, .g = 1, .b = 1, .a = 0.10 };

const Scene = struct {
    pub fn view(_: *Scene, c: *ui.Context) void {
        const root = ui.div(c).column().sizeFull().p(20).bg(.{ .r = 0.12, .g = 0.11, .b = 0.09, .a = 1 });
        defer root.end();
        const box = ui.div(c).w(200).h(100).rounded(26).bg(fill).border(edge).borderW(1);
        box.end();
    }
};

test "a faint border round a rounded box is never lighter than over its fill" {
    var s: Scene = .{};
    var t: ui.Tester = undefined;
    try t.init(testing.allocator, .init(&s, Scene.view), .{ .width = 240, .height = 140 });
    defer t.deinit();
    t.settle(1);
    const px = try t.render(testing.allocator);
    defer px.deinit(testing.allocator);
    // The border over the fill, the lightest anything on the box may be.
    const ceiling = fill.r + edge.a * (1 - fill.r);
    var lightest: f32 = 0;
    // The top-left corner's curve, at the display's scale.
    const sc: usize = @intFromFloat(t.scale);
    for (20 * sc..50 * sc) |y| for (20 * sc..50 * sc) |x| {
        const i = (y * px.width + x) * 4;
        // BGRA: the red channel.
        lightest = @max(lightest, @as(f32, @floatFromInt(px.bytes[i + 2])) / 255);
    };
    try testing.expect(lightest <= ceiling + 0.02);
}
