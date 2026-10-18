//! What the renderers draw, whichever draws it: instanced quads that are
//! rounded rectangles with borders, glyphs and icons from the atlas,
//! shadows, or pictures from the image atlas, each clipped. Metal draws them on macOS (`metal.zig`, with
//! `shader.metal`); `raster.zig` draws the same pixels on the CPU.
const types = @import("types.zig");
const std = @import("std");

/// One quad, as the shader reads it.
pub const Instance = extern struct {
    rect: [4]f32,
    color: [4]f32,
    border_color: [4]f32 = .{ 0, 0, 0, 0 },
    uv: [4]f32 = .{ 0, 0, 0, 0 },
    clip: [4]f32 = .{ -1e6, -1e6, 1e6, 1e6 },
    radius: f32 = 0,
    border_width: f32 = 0,
    kind: f32 = 0,
    pad: f32 = 0,
};

pub const Kind = struct {
    pub const quad: f32 = 0;
    pub const text: f32 = 1;
    pub const shadow: f32 = 2;
    /// A picture from the image atlas (`images.zig`), its corners rounded.
    pub const image: f32 = 3;
};

pub fn color4(c: types.Color) [4]f32 {
    return .{ c.r, c.g, c.b, c.a };
}

pub fn clip4(r: types.Rect) [4]f32 {
    return .{ r.x, r.y, r.x + r.w, r.y + r.h };
}

/// A rendered frame: BGRA, premultiplied, `width * 4` bytes per row.
pub const Pixels = struct {
    bytes: []u8,
    width: usize,
    height: usize,

    pub fn deinit(p: Pixels, gpa: std.mem.Allocator) void {
        gpa.free(p.bytes);
    }
};
