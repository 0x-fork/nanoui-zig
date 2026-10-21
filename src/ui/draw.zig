//! A box to draw in (`ui.canvas`): lines, filled triangles and polygons,
//! circles and rounded rectangles, at points within the box. They are
//! drawn as the frame paints the box, clipped to it, and kept only for
//! the frame, like everything else in it. A map, a chart, a diagram.
//!
//!     const cv = ui.canvas(c, .{ .width = .fill, .height = .{ .px = 200 } });
//!     cv.polyline(&points, .{ .width = 2, .color = c.theme.accent });
//!     cv.fill(&outline, c.theme.muted);
const std = @import("std");
const types = @import("types.zig");
const gpu = @import("gpu.zig");
const Context = @import("context.zig").Context;

const Point = types.Point;
const Color = types.Color;

pub const Stroke = struct {
    width: f32 = 1,
    color: Color,
    /// A dash's length and the gap after it, in points: null for a solid line.
    dash: ?[2]f32 = null,
};

pub const Canvas = struct {
    c: *Context,
    /// What is drawn, at points within the box.
    shapes: std.ArrayList(gpu.Instance) = .empty,
    /// The box's size at the last layout: zero in its first frame (which
    /// is built again once it has one).
    size: types.Size = .{},

    fn add(cv: *Canvas, i: gpu.Instance) void {
        cv.shapes.append(cv.c.alloc(), i) catch {};
    }

    /// A line from `a` to `b`, its ends round.
    pub fn line(cv: *Canvas, a: Point, b: Point, s: Stroke) void {
        cv.dashed(a, b, s, 0);
    }

    fn dashed(cv: *Canvas, a: Point, b: Point, s: Stroke, phase: f32) void {
        const e = s.width * 0.5 + 1;
        const dash = s.dash orelse .{ 0, 0 };
        cv.add(.{
            .rect = .{ @min(a.x, b.x) - e, @min(a.y, b.y) - e, @abs(b.x - a.x) + 2 * e, @abs(b.y - a.y) + 2 * e },
            .color = gpu.color4(s.color),
            .uv = .{ a.x, a.y, b.x, b.y },
            .border_color = .{ dash[0], dash[1], phase, 0 },
            .border_width = s.width,
            .kind = gpu.Kind.segment,
        });
    }

    /// Lines through `points` in turn, a dash carrying on round each corner.
    pub fn polyline(cv: *Canvas, points: []const Point, s: Stroke) void {
        var along: f32 = 0;
        for (points[0..points.len -| 1], points[@min(1, points.len)..]) |a, b| {
            cv.dashed(a, b, s, along);
            along += @sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
        }
    }

    /// A filled triangle. `smooth`: its edges smoothed (1 `a` to `b`, 2 `b`
    /// to `p`, 4 `p` to `a`); leave out those it shares with another, so
    /// the two meet without a seam.
    pub fn triangle(cv: *Canvas, a: Point, b: Point, p: Point, color: Color, smooth: u3) void {
        const x0 = @min(a.x, @min(b.x, p.x));
        const y0 = @min(a.y, @min(b.y, p.y));
        cv.add(.{
            .rect = .{ x0, y0, @max(a.x, @max(b.x, p.x)) - x0, @max(a.y, @max(b.y, p.y)) - y0 },
            .color = gpu.color4(color),
            .uv = .{ a.x, a.y, b.x, b.y },
            .border_color = .{ p.x, p.y, @floatFromInt(smooth), 0 },
            .kind = gpu.Kind.triangle,
        });
    }

    /// Triangles made already (`triangulate`): `tris` index `points`, its
    /// edges smoothed as `tris` says.
    pub fn mesh(cv: *Canvas, points: []const Point, tris: []const Triangle, color: Color) void {
        for (tris) |t| cv.triangle(points[t.v[0]], points[t.v[1]], points[t.v[2]], color, t.smooth);
    }

    /// A polygon filled (its outline once round, either way; no holes),
    /// its outline smoothed.
    pub fn fill(cv: *Canvas, points: []const Point, color: Color) void {
        const tris = triangulate(cv.c.alloc(), points) catch return;
        cv.mesh(points, tris, color);
    }

    pub fn circle(cv: *Canvas, center: Point, r: f32, color: Color) void {
        cv.rect(.{ .x = center.x - r, .y = center.y - r, .w = 2 * r, .h = 2 * r }, color, r);
    }

    pub fn rect(cv: *Canvas, r: types.Rect, color: Color, radius: f32) void {
        cv.add(.{ .rect = .{ r.x, r.y, r.w, r.h }, .color = gpu.color4(color), .radius = radius });
    }

    /// A ring: a circle's outline `width` wide.
    pub fn ring(cv: *Canvas, center: Point, r: f32, width: f32, color: Color) void {
        cv.add(.{
            .rect = .{ center.x - r, center.y - r, 2 * r, 2 * r },
            .color = .{ 0, 0, 0, 0 },
            .border_color = gpu.color4(color),
            .border_width = width,
            .radius = r,
        });
    }
};

/// A box to draw in, sized and placed by `style`.
pub fn canvas(c: *Context, style: types.Style) *Canvas {
    const cv = c.alloc().create(Canvas) catch @panic("nanoui: out of memory");
    const id = c.peekId(null);
    cv.* = .{ .c = c };
    if (c.rects.get(id)) |r| cv.size = .{ .w = r.w, .h = r.h } else c.changed = true;
    _ = c.leaf(style, .{ .canvas = cv }, null);
    return cv;
}

pub const Triangle = struct {
    /// Indices of its corners.
    v: [3]u32,
    /// Which of its edges are the polygon's outline (see `Canvas.triangle`).
    smooth: u3 = 0,
};

/// A simple polygon (no holes; either way round) as triangles, by
/// clipping ears: each corner that bulges outwards with no other corner
/// inside the triangle it makes is cut off in turn. Edges on the outline
/// are marked smooth.
pub fn triangulate(gpa: std.mem.Allocator, points: []const Point) ![]Triangle {
    const n = points.len;
    if (n < 3) return &.{};
    var out: std.ArrayList(Triangle) = try .initCapacity(gpa, n - 2);
    errdefer out.deinit(gpa);
    // The corners left, as a ring.
    const next = try gpa.alloc(u32, n);
    defer gpa.free(next);
    const prev = try gpa.alloc(u32, n);
    defer gpa.free(prev);
    for (0..n) |k| {
        next[k] = @intCast((k + 1) % n);
        prev[k] = @intCast((k + n - 1) % n);
    }
    var area: f32 = 0;
    for (0..n) |k| area += cross(points[k], points[(k + 1) % n], .{});
    const side: f32 = if (area < 0) -1 else 1;

    var left = n;
    var cur: u32 = 0;
    var tried: usize = 0;
    while (left > 3) {
        const a = prev[cur];
        const b = next[cur];
        if (isEar(points, prev, next, a, cur, b, side) or tried > left) {
            try out.append(gpa, tri(n, a, cur, b));
            next[a] = b;
            prev[b] = a;
            left -= 1;
            tried = 0;
            cur = b;
        } else {
            tried += 1;
            cur = b;
        }
    }
    try out.append(gpa, tri(n, prev[cur], cur, next[cur]));
    return out.toOwnedSlice(gpa);
}

fn cross(o: Point, a: Point, b: Point) f32 {
    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
}

/// The triangle `a`, `b`, `p`, its edges along the outline (consecutive
/// corners of the `n`) smooth.
fn tri(n: usize, a: u32, b: u32, p: u32) Triangle {
    const outline = struct {
        fn f(count: usize, x: u32, y: u32) bool {
            return (x + 1) % count == y or (y + 1) % count == x;
        }
    }.f;
    var smooth: u3 = 0;
    if (outline(n, a, b)) smooth |= 1;
    if (outline(n, b, p)) smooth |= 2;
    if (outline(n, p, a)) smooth |= 4;
    return .{ .v = .{ a, b, p }, .smooth = smooth };
}

fn isEar(points: []const Point, prev: []const u32, next: []const u32, a: u32, b: u32, p: u32, side: f32) bool {
    const pa = points[a];
    const pb = points[b];
    const pp = points[p];
    // Bulging outwards (as the polygon turns), not flat.
    if (side * cross(pa, pb, pp) <= 0) return false;
    // No other corner left inside it.
    var k = next[p];
    while (k != a) : (k = next[k]) {
        const q = points[k];
        if (q.x == pa.x and q.y == pa.y or q.x == pb.x and q.y == pb.y or q.x == pp.x and q.y == pp.y) continue;
        if (side * cross(pa, pb, q) >= 0 and side * cross(pb, pp, q) >= 0 and side * cross(pp, pa, q) >= 0) return false;
    }
    _ = prev;
    return true;
}

test "a square is two triangles, its outline smooth and its diagonal not" {
    const sq = [_]Point{ .{ .x = 0, .y = 0 }, .{ .x = 10, .y = 0 }, .{ .x = 10, .y = 10 }, .{ .x = 0, .y = 10 } };
    const tris = try triangulate(std.testing.allocator, &sq);
    defer std.testing.allocator.free(tris);
    try std.testing.expectEqual(@as(usize, 2), tris.len);
    var smooth_edges: usize = 0;
    for (tris) |t| smooth_edges += @popCount(t.smooth);
    try std.testing.expectEqual(@as(usize, 4), smooth_edges);
}

test "a concave polygon's triangles cover its area exactly" {
    // An L, clockwise on the screen and then the other way.
    const l = [_]Point{ .{ .x = 0, .y = 0 }, .{ .x = 20, .y = 0 }, .{ .x = 20, .y = 10 }, .{ .x = 10, .y = 10 }, .{ .x = 10, .y = 30 }, .{ .x = 0, .y = 30 } };
    var rev: [l.len]Point = undefined;
    for (l, 0..) |p, k| rev[l.len - 1 - k] = p;
    for ([_][]const Point{ &l, &rev }) |poly| {
        const tris = try triangulate(std.testing.allocator, poly);
        defer std.testing.allocator.free(tris);
        try std.testing.expectEqual(poly.len - 2, tris.len);
        var area: f32 = 0;
        for (tris) |t| area += @abs(cross(poly[t.v[0]], poly[t.v[1]], poly[t.v[2]])) / 2;
        try std.testing.expectApproxEqAbs(@as(f32, 400), area, 0.01);
    }
}
