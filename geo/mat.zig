const std = @import("std");
const math = std.math;

usingnamespace @import("vec.zig");
usingnamespace @import("rotor.zig");
usingnamespace @import("xform.zig");

/// A 3x3 matrix.  When required to choose, this library uses
/// the column-major convention.
pub const Mat3 = extern struct {
    pub x: Vec3,
    pub y: Vec3,
    pub z: Vec3,

    pub const Identity = Mat3{
        .x = Vec3.X,
        .y = Vec3.Y,
        .z = Vec3.Z,
    };

    pub inline fn row(self: Mat3, comptime n: usize) Vec3 {
        return switch (n) {
            0 => Vec3.init(self.x.x, self.y.x, self.z.x),
            1 => Vec3.init(self.x.y, self.y.y, self.z.y),
            2 => Vec3.init(self.x.z, self.y.z, self.z.z),
            else => @compileError("row must be 0, 1, or 2"),
        };
    }

    pub inline fn col(self: Mat3, comptime n: usize) Vec3 {
        return switch (n) {
            0 => self.x,
            1 => self.y,
            2 => self.z,
            else => @compileError("col must be 0, 1, or 2"),
        };
    }

    pub fn preScaleVec(l: Mat3, r: Vec3) Mat3 {
        return Mat3{
            .x = l.x.scale(r.x),
            .y = l.y.scale(r.y),
            .z = l.z.scale(r.z),
        };
    }

    pub fn postScaleVec(l: Mat3, r: Vec3) Mat3 {
        return Mat3{
            .x = l.x.mul(r),
            .y = l.y.mul(r),
            .z = l.z.mul(r),
        };
    }

    pub fn scale(l: Mat3, r: f32) Mat3 {
        return Mat3{
            .x = l.x.scale(r),
            .y = l.y.scale(r),
            .z = l.z.scale(r),
        };
    }

    pub fn preRotate(self: Mat3, r: Rotor3) Mat3 {
        return Generic.preRotateMat3(self, r);
    }

    pub fn postRotate(self: Mat3, r: Rotor3) Mat3 {
        return Generic.preRotateMat3(self, r);
    }

    pub fn mulVec(l: Mat3, r: Vec3) Vec3 {
        return Generic.mulMat3Vec3(l, r);
    }

    pub fn transpose(self: Mat3) Mat3 {
        return Generic.transpose3x3(self);
    }

    pub fn determinant(m: Mat3) f32 {
        return Generic.determinant3x3(m);
    }

    pub fn inverse(m: Mat3) !Mat3 {
        return try Generic.inverse3x3(m);
    }

    pub fn transposedInverse(m: Mat3) !Mat3 {
        return try Generic.transposedInverse3x3(m);
    }

    pub fn mulMat(l: Mat3, r: Mat3) Mat3 {
        return Generic.mulMat3Mat3(l, r);
    }

    pub fn mulMat4x3(l: Mat3, r: Mat4x3) Mat4x3 {
        return Generic.mulMat3Mat4x3(l, r);
    }

    pub fn mulMat4(l: Mat3, r: Mat4) Mat4 {
        return Generic.mulMat3Mat4(l, r);
    }

    pub inline fn asBuf(self: *Mat3) *[9]f32 {
        return @ptrCast(*[9]f32, self);
    }

    pub inline fn asGrid(self: *Mat3) *[3][3]f32 {
        return @ptrCast(*[3][3]f32, self);
    }

    pub inline fn toMat4x3(self: Mat3, translation: Vec3) Mat4x3 {
        return Mat4x3{
            .x = self.x,
            .y = self.y,
            .z = self.z,
            .w = translation,
        };
    }

    pub inline fn toMat4(self: Mat3, translation: Vec3) Mat4 {
        return Mat4{
            .x = self.x.toVec4(0),
            .y = self.y.toVec4(0),
            .z = self.z.toVec4(0),
            .w = translation.toVec4(1),
        };
    }

    /// Constructs a Mat4 with this matrix as the rotation/scale part,
    pub inline fn toMat4Projection(self: Mat3, translation: Vec3, projection: Vec4) Mat4 {
        return Mat4{
            .x = self.x.toVec4(projection.x),
            .y = self.y.toVec4(projection.y),
            .z = self.z.toVec4(projection.z),
            .w = translation.toVec4(projection.w),
        };
    }
};

/// A 4x3 matrix.  When required to choose, this library uses
/// the column-major convention.
pub const Mat4x3 = extern struct {
    pub x: Vec3,
    pub y: Vec3,
    pub z: Vec3,
    pub w: Vec3,

    pub const Identity = Mat4x3{
        .x = Vec3.X,
        .y = Vec3.Y,
        .z = Vec3.Z,
        .w = Vec3.Zero,
    };

    pub inline fn row(self: Mat4x3, comptime n: usize) Vec4 {
        return switch (n) {
            0 => Vec4.init(self.x.x, self.y.x, self.z.x, self.w.x),
            1 => Vec4.init(self.x.y, self.y.y, self.z.y, self.w.y),
            2 => Vec4.init(self.x.z, self.y.z, self.z.z, self.w.z),
            else => @compileError("row must be 0, 1, or 2"),
        };
    }

    pub inline fn col(self: Mat4x3, comptime n: usize) Vec3 {
        return switch (n) {
            0 => self.x,
            1 => self.y,
            2 => self.z,
            3 => self.w,
            else => @compileError("col must be 0, 1, 2, or 3"),
        };
    }

    pub fn preScaleVec(l: Mat4x3, r: Vec3) Mat4x3 {
        return Mat4x3{
            .x = l.x.scale(r.x),
            .y = l.y.scale(r.y),
            .z = l.z.scale(r.z),
            .w = l.w,
        };
    }

    pub fn postScaleVec(l: Mat4x3, r: Vec3) Mat4x3 {
        return Mat4x3{
            .x = l.x.mul(r),
            .y = l.y.mul(r),
            .z = l.z.mul(r),
            .w = l.w.mul(r),
        };
    }

    pub fn preScale(l: Mat4x3, r: f32) Mat4x3 {
        return Mat4x3{
            .x = l.x.scale(r),
            .y = l.y.scale(r),
            .z = l.z.scale(r),
            .w = l.w,
        };
    }

    pub fn postScale(l: Mat4x3, r: f32) Mat4x3 {
        return Mat4x3{
            .x = l.x.scale(r),
            .y = l.y.scale(r),
            .z = l.z.scale(r),
            .w = l.w.scale(r),
        };
    }

    pub inline fn preTranslate(l: Mat4x3, trans: Vec3) Mat4x3 {
        return Mat4x3{
            .x = l.x,
            .y = l.y,
            .z = l.z,
            .w = Vec3{
                .x = l.x.x * trans.x + l.y.x * trans.y + l.z.x * trans.z + l.w.x,
                .y = l.x.y * trans.x + l.y.y * trans.y + l.z.y * trans.z + l.w.y,
                .z = l.x.z * trans.x + l.y.z * trans.y + l.z.z * trans.z + l.w.z,
            },
        };
    }

    pub inline fn postTranslate(l: Mat4x3, trans: Vec3) Mat4x3 {
        return Mat4x3{
            .x = l.x,
            .y = l.y,
            .z = l.z,
            .w = l.w.add(trans),
        };
    }

    pub fn preRotate(self: Mat4x3, r: Rotor3) Mat4x3 {
        return Generic.preRotateMat4x3(self, r);
    }

    pub fn postRotate(self: Mat4x3, r: Rotor3) Mat4x3 {
        return Generic.preRotateMat4x3(self, r);
    }

    pub fn mul3x3Vec(l: Mat4x3, r: Vec3) Vec3 {
        return Generic.mulMat3Vec3(l, r);
    }

    pub fn mulVec3(l: Mat4x3, r: Vec3) Vec3 {
        return Generic.mulMat4x3Vec3(l, r);
    }

    pub fn mulVec(l: Mat4x3, r: Vec4) Vec3 {
        return Generic.mulMat4x3Vec4(l, r);
    }

    pub fn inverse(self: Mat4x3) !Mat4x3 {
        return try Generic.inverse4x3(self);
    }

    pub fn mulMat3(l: Mat4x3, r: Mat3) Mat4x3 {
        return Generic.mulMat4x3Mat3(l, r);
    }

    pub fn mulMat(l: Mat4x3, r: Mat4x3) Mat4x3 {
        return Generic.mulMat4x3Mat4x3(l, r);
    }

    pub fn mulMat4(l: Mat4x3, r: Mat4) Mat4 {
        return Generic.mulMat4x3Mat4(l, r);
    }

    pub inline fn asBuf(self: *Mat4x3) *[12]f32 {
        return @ptrCast(*[12]f32, self);
    }

    pub inline fn asGrid(self: *Mat4x3) *[4][3]f32 {
        return @ptrCast(*[4][3]f32, self);
    }

    pub inline fn asMat3(self: *Mat4x3) *Mat3 {
        return @ptrCast(*Mat3, self);
    }

    pub inline fn toMat3(self: Mat4x3) Mat3 {
        return Mat3{
            .x = self.x,
            .y = self.y,
            .z = self.z,
        };
    }

    /// Constructs a Mat4 with this matrix as the rotation/scale/translation part,
    pub inline fn toMat4(self: Mat4x3) Mat4 {
        return Mat4{
            .x = self.x.toVec4(0),
            .y = self.y.toVec4(0),
            .z = self.z.toVec4(0),
            .w = self.w.toVec4(1),
        };
    }

    /// Constructs a Mat4 with this matrix as the rotation/scale/translation part,
    pub inline fn toMat4Projection(self: Mat4x3, projection: Vec4) Mat4 {
        return Mat4{
            .x = self.x.toVec4(projection.x),
            .y = self.y.toVec4(projection.y),
            .z = self.z.toVec4(projection.z),
            .w = self.w.toVec4(projection.w),
        };
    }
};

/// A 4x4 matrix.  When required to choose, this library uses
/// the column-major convention.
pub const Mat4 = extern struct {
    pub x: Vec4,
    pub y: Vec4,
    pub z: Vec4,
    pub w: Vec4,

    pub const Identity = Mat4{
        .x = Vec4.X,
        .y = Vec4.Y,
        .z = Vec4.Z,
        .w = Vec4.W,
    };

    pub inline fn row(self: Mat4, comptime n: usize) Vec4 {
        return switch (n) {
            0 => Vec4.init(self.x.x, self.y.x, self.z.x, self.w.x),
            1 => Vec4.init(self.x.y, self.y.y, self.z.y, self.w.y),
            2 => Vec4.init(self.x.z, self.y.z, self.z.z, self.w.z),
            3 => Vec4.init(self.x.w, self.y.w, self.z.w, self.w.w),
            else => @compileError("row must be 0, 1, 2, or 3"),
        };
    }

    pub inline fn col(self: Mat4, comptime n: usize) Vec4 {
        return switch (n) {
            0 => self.x,
            1 => self.y,
            2 => self.z,
            3 => self.w,
            else => @compileError("col must be 0, 1, 2, or 3"),
        };
    }

    pub fn preScaleVec(l: Mat4, r: Vec3) Mat4 {
        return Mat4{
            .x = l.x.scale(r.x),
            .y = l.y.scale(r.y),
            .z = l.z.scale(r.z),
            .w = l.w,
        };
    }

    pub fn postScaleVec(l: Mat4, r: Vec3) Mat4 {
        return Mat4{
            .x = Vec4.init(l.x.x * r.x, l.x.y * r.y, l.x.z * r.z, l.x.w),
            .y = Vec4.init(l.y.x * r.x, l.y.y * r.y, l.y.z * r.z, l.y.w),
            .z = Vec4.init(l.z.x * r.x, l.z.y * r.y, l.z.z * r.z, l.z.w),
            .w = Vec4.init(l.w.z * r.x, l.w.y * r.y, l.w.z * r.z, l.w.w),
        };
    }

    pub fn preScale(l: Mat4, r: f32) Mat4 {
        return Mat4{
            .x = l.x.scale(r),
            .y = l.y.scale(r),
            .z = l.z.scale(r),
            .w = l.w,
        };
    }

    pub fn postScale(l: Mat4, r: f32) Mat4 {
        return Mat4x3{
            .x = l.x.scale(r),
            .y = l.y.scale(r),
            .z = l.z.scale(r),
            .w = l.w.scale(r),
        };
    }

    pub inline fn preTranslate(l: Mat4, trans: Vec3) Mat4 {
        return Mat4{
            .x = l.x,
            .y = l.y,
            .z = l.z,
            .w = Vec4{
                .x = l.x.x * trans.x + l.y.x * trans.y + l.z.x * trans.z + l.w.x,
                .y = l.x.y * trans.x + l.y.y * trans.y + l.z.y * trans.z + l.w.y,
                .z = l.x.z * trans.x + l.y.z * trans.y + l.z.z * trans.z + l.w.z,
                .w = l.w.w,
            },
        };
    }

    pub inline fn postTranslate(l: Mat4, trans: Vec3) Mat4 {
        return Mat4{
            .x = l.x,
            .y = l.y,
            .z = l.z,
            .w = Vec4{
                .x = l.w.x + trans.x,
                .y = l.w.y + trans.y,
                .z = l.w.z + trans.z,
                .w = l.w.w,
            },
        };
    }

    pub fn project(l: Mat4, r: Vec3) Vec3 {
        const raw = Generic.mulMat4x3Vec3(l, r);
        const w = l.x.w * r.x + l.y.w * r.y + l.z.w * r.z + l.w.w;
        return raw.scale(1.0 / w);
    }

    pub fn mulVec(l: Mat4, r: Vec4) Vec4 {
        return Generic.mulMat4Vec4(l, r);
    }

    pub fn mulMat3(l: Mat4, r: Mat3) Mat4 {
        return Generic.mulMat4Mat3(l, r);
    }

    pub fn mulMat4x3(l: Mat4, r: Mat4x3) Mat4 {
        return Generic.mulMat4Mat4x3(l, r);
    }

    pub fn mulMat(l: Mat4, r: Mat4) Mat4 {
        return Generic.mulMat4Mat4(l, r);
    }

    pub inline fn asBuf(self: *Mat4) *[16]f32 {
        return @ptrCast(*[16]f32, self);
    }

    pub inline fn asGrid(self: *Mat4) *[4][4]f32 {
        return @ptrCast(*[4][4]f32, self);
    }

    pub inline fn toMat3(self: Mat4) Mat3 {
        return Mat3{
            .x = self.x.toVec3(),
            .y = self.y.toVec3(),
            .z = self.z.toVec3(),
        };
    }

    pub inline fn toMat4x3(self: Mat4) Mat4x3 {
        return Mat4x3{
            .x = self.x.toVec3(),
            .y = self.y.toVec3(),
            .z = self.z.toVec3(),
            .w = self.w.toVec3(),
        };
    }
};

pub const Generic = struct {
    pub fn determinant3x3(m: var) f32 {
        return m.x.x * (m.y.y * m.z.z - m.y.z * m.z.y) -
            m.x.y * (m.y.x * m.z.z - m.y.z * m.z.x) +
            m.x.z * (m.y.x * m.z.y - m.y.y * m.z.x);
    }

    pub fn inverse3x3(m: var) !Mat3 {
        const det = @inlineCall(determinant3x3, m);
        const mult = 1.0 / det;
        if (!math.isFinite(mult)) return error.Singular;
        return Mat3{
            .x = Vec3{
                .x = (m.y.y * m.z.z - m.z.y * m.y.z) * mult,
                .y = (m.x.z * m.z.y - m.x.y * m.z.z) * mult,
                .z = (m.x.y * m.y.z - m.x.z * m.y.y) * mult,
            },
            .y = Vec3{
                .x = (m.y.z * m.z.x - m.y.x * m.z.z) * mult,
                .y = (m.x.x * m.z.z - m.x.z * m.z.x) * mult,
                .z = (m.y.x * m.x.z - m.x.x * m.y.z) * mult,
            },
            .z = Vec3{
                .x = (m.y.x * m.z.y - m.z.x * m.y.y) * mult,
                .y = (m.z.x * m.x.y - m.x.x * m.z.y) * mult,
                .z = (m.x.x * m.y.y - m.y.x * m.x.y) * mult,
            },
        };
    }

    pub fn transposedInverse3x3(m: var) !Mat3 {
        const det = @inlineCall(determinant3x3, m);
        const mult = 1.0 / det;
        if (!math.isFinite(mult)) return error.Singular;
        return Mat3{
            .x = Vec3{
                .x = (m.y.y * m.z.z - m.z.y * m.y.z) * mult,
                .y = (m.y.z * m.z.x - m.y.x * m.z.z) * mult,
                .z = (m.y.x * m.z.y - m.z.x * m.y.y) * mult,
            },
            .y = Vec3{
                .x = (m.x.z * m.z.y - m.x.y * m.z.z) * mult,
                .y = (m.x.x * m.z.z - m.x.z * m.z.x) * mult,
                .z = (m.z.x * m.x.y - m.x.x * m.z.y) * mult,
            },
            .z = Vec3{
                .x = (m.x.y * m.y.z - m.x.z * m.y.y) * mult,
                .y = (m.y.x * m.x.z - m.x.x * m.y.z) * mult,
                .z = (m.x.x * m.y.y - m.y.x * m.x.y) * mult,
            },
        };
    }

    pub fn transpose3x3(m: var) Mat3 {
        return Mat3{
            .x = Vec3{
                .x = m.x.x,
                .y = m.y.x,
                .z = m.z.x,
            },
            .y = Vec3{
                .x = m.x.y,
                .y = m.y.y,
                .z = m.z.y,
            },
            .z = Vec3{
                .x = m.x.z,
                .y = m.y.z,
                .z = m.z.z,
            },
        };
    }

    pub fn inverse4x3(m: var) !Mat4x3 {
        var result: Mat4x3 = undefined;
        result.asMat3().* = try inverse3x3(m);
        result.w = Vec3.init(-m.w.x, -m.w.y, -m.w.z);
        return result;
    }

    pub fn mulMat3Vec3(l: var, r: var) Vec3 {
        return Vec3{
            .x = l.x.x * r.x + l.y.x * r.y + l.z.x * r.z,
            .y = l.x.y * r.x + l.y.y * r.y + l.z.y * r.z,
            .z = l.x.z * r.x + l.y.z * r.y + l.z.z * r.z,
        };
    }

    pub fn mulMat4x3Vec3(l: var, r: var) Vec3 {
        return Vec3{
            .x = l.x.x * r.x + l.y.x * r.y + l.z.x * r.z + l.w.x,
            .y = l.x.y * r.x + l.y.y * r.y + l.z.y * r.z + l.w.y,
            .z = l.x.z * r.x + l.y.z * r.y + l.z.z * r.z + l.w.z,
        };
    }

    pub fn mulMat4x3Vec4(l: var, r: var) Vec3 {
        return Vec3{
            .x = l.x.x * r.x + l.y.x * r.y + l.z.x * r.z + l.w.x * r.w,
            .y = l.x.y * r.x + l.y.y * r.y + l.z.y * r.z + l.w.y * r.w,
            .z = l.x.z * r.x + l.y.z * r.y + l.z.z * r.z + l.w.z * r.w,
        };
    }

    pub fn mulMat4Vec4(l: var, r: var) Vec4 {
        return Vec4{
            .x = l.x.x * r.x + l.y.x * r.y + l.z.x * r.z + l.w.x * r.w,
            .y = l.x.y * r.x + l.y.y * r.y + l.z.y * r.z + l.w.y * r.w,
            .z = l.x.z * r.x + l.y.z * r.y + l.z.z * r.z + l.w.z * r.w,
            .w = l.x.w * r.x + l.y.w * r.y + l.z.w * r.z + l.w.w * r.w,
        };
    }

    pub fn mulMat3Mat3(l: var, r: var) Mat3 {
        return Mat3{
            .x = Vec3{
                .x = l.x.x * r.x.x + l.y.x * r.x.y + l.z.x * r.x.z,
                .y = l.x.y * r.x.x + l.y.y * r.x.y + l.z.y * r.x.z,
                .z = l.x.z * r.x.x + l.y.z * r.x.y + l.z.z * r.x.z,
            },
            .y = Vec3{
                .x = l.x.x * r.y.x + l.y.x * r.y.y + l.z.x * r.y.z,
                .y = l.x.y * r.y.x + l.y.y * r.y.y + l.z.y * r.y.z,
                .z = l.x.z * r.y.x + l.y.z * r.y.y + l.z.z * r.y.z,
            },
            .z = Vec3{
                .x = l.x.x * r.z.x + l.y.x * r.z.y + l.z.x * r.z.z,
                .y = l.x.y * r.z.x + l.y.y * r.z.y + l.z.y * r.z.z,
                .z = l.x.z * r.z.x + l.y.z * r.z.y + l.z.z * r.z.z,
            },
        };
    }

    pub fn mulMat3Mat4x3(l: var, r: var) Mat4x3 {
        return Mat4x3{
            .x = Vec3{
                .x = l.x.x * r.x.x + l.y.x * r.x.y + l.z.x * r.x.z,
                .y = l.x.y * r.x.x + l.y.y * r.x.y + l.z.y * r.x.z,
                .z = l.x.z * r.x.x + l.y.z * r.x.y + l.z.z * r.x.z,
            },
            .y = Vec3{
                .x = l.x.x * r.y.x + l.y.x * r.y.y + l.z.x * r.y.z,
                .y = l.x.y * r.y.x + l.y.y * r.y.y + l.z.y * r.y.z,
                .z = l.x.z * r.y.x + l.y.z * r.y.y + l.z.z * r.y.z,
            },
            .z = Vec3{
                .x = l.x.x * r.z.x + l.y.x * r.z.y + l.z.x * r.z.z,
                .y = l.x.y * r.z.x + l.y.y * r.z.y + l.z.y * r.z.z,
                .z = l.x.z * r.z.x + l.y.z * r.z.y + l.z.z * r.z.z,
            },
            .w = Vec3{
                .x = l.x.x * r.w.x + l.y.x * r.w.y + l.z.x * r.w.z,
                .y = l.x.y * r.w.x + l.y.y * r.w.y + l.z.y * r.w.z,
                .z = l.x.z * r.w.x + l.y.z * r.w.y + l.z.z * r.w.z,
            },
        };
    }

    pub fn mulMat4x3Mat3(l: var, r: var) Mat4x3 {
        return Mat4x3{
            .x = Vec3{
                .x = l.x.x * r.x.x + l.y.x * r.x.y + l.z.x * r.x.z,
                .y = l.x.y * r.x.x + l.y.y * r.x.y + l.z.y * r.x.z,
                .z = l.x.z * r.x.x + l.y.z * r.x.y + l.z.z * r.x.z,
            },
            .y = Vec3{
                .x = l.x.x * r.y.x + l.y.x * r.y.y + l.z.x * r.y.z,
                .y = l.x.y * r.y.x + l.y.y * r.y.y + l.z.y * r.y.z,
                .z = l.x.z * r.y.x + l.y.z * r.y.y + l.z.z * r.y.z,
            },
            .z = Vec3{
                .x = l.x.x * r.z.x + l.y.x * r.z.y + l.z.x * r.z.z,
                .y = l.x.y * r.z.x + l.y.y * r.z.y + l.z.y * r.z.z,
                .z = l.x.z * r.z.x + l.y.z * r.z.y + l.z.z * r.z.z,
            },
            .w = l.w,
        };
    }

    pub fn mulMat3Mat4(l: var, r: var) Mat4 {
        return Mat4{
            .x = Vec4{
                .x = l.x.x * r.x.x + l.y.x * r.x.y + l.z.x * r.x.z,
                .y = l.x.y * r.x.x + l.y.y * r.x.y + l.z.y * r.x.z,
                .z = l.x.z * r.x.x + l.y.z * r.x.y + l.z.z * r.x.z,
                .w = r.x.w,
            },
            .y = Vec4{
                .x = l.x.x * r.y.x + l.y.x * r.y.y + l.z.x * r.y.z,
                .y = l.x.y * r.y.x + l.y.y * r.y.y + l.z.y * r.y.z,
                .z = l.x.z * r.y.x + l.y.z * r.y.y + l.z.z * r.y.z,
                .w = r.y.w,
            },
            .z = Vec4{
                .x = l.x.x * r.z.x + l.y.x * r.z.y + l.z.x * r.z.z,
                .y = l.x.y * r.z.x + l.y.y * r.z.y + l.z.y * r.z.z,
                .z = l.x.z * r.z.x + l.y.z * r.z.y + l.z.z * r.z.z,
                .w = r.z.w,
            },
            .w = Vec4{
                .x = l.x.x * r.w.x + l.y.x * r.w.y + l.z.x * r.w.z,
                .y = l.x.y * r.w.x + l.y.y * r.w.y + l.z.y * r.w.z,
                .z = l.x.z * r.w.x + l.y.z * r.w.y + l.z.z * r.w.z,
                .w = r.w.w,
            },
        };
    }

    pub fn mulMat4Mat3(l: var, r: var) Mat4 {
        return Mat4{
            .x = Vec4{
                .x = l.x.x * r.x.x + l.y.x * r.x.y + l.z.x * r.x.z,
                .y = l.x.y * r.x.x + l.y.y * r.x.y + l.z.y * r.x.z,
                .z = l.x.z * r.x.x + l.y.z * r.x.y + l.z.z * r.x.z,
                .w = l.x.w * r.x.x + l.y.w * r.x.y + l.z.w * r.x.z,
            },
            .y = Vec4{
                .x = l.x.x * r.y.x + l.y.x * r.y.y + l.z.x * r.y.z,
                .y = l.x.y * r.y.x + l.y.y * r.y.y + l.z.y * r.y.z,
                .z = l.x.z * r.y.x + l.y.z * r.y.y + l.z.z * r.y.z,
                .w = l.x.w * r.y.x + l.y.w * r.y.y + l.z.w * r.y.z,
            },
            .z = Vec4{
                .x = l.x.x * r.z.x + l.y.x * r.z.y + l.z.x * r.z.z,
                .y = l.x.y * r.z.x + l.y.y * r.z.y + l.z.y * r.z.z,
                .z = l.x.z * r.z.x + l.y.z * r.z.y + l.z.z * r.z.z,
                .w = l.x.w * r.z.x + l.y.w * r.z.y + l.z.w * r.z.z,
            },
            .w = l.w,
        };
    }

    pub fn mulMat4x3Mat4x3(l: var, r: var) Mat4x3 {
        return Mat4x3{
            .x = Vec3{
                .x = l.x.x * r.x.x + l.y.x * r.x.y + l.z.x * r.x.z,
                .y = l.x.y * r.x.x + l.y.y * r.x.y + l.z.y * r.x.z,
                .z = l.x.z * r.x.x + l.y.z * r.x.y + l.z.z * r.x.z,
            },
            .y = Vec3{
                .x = l.x.x * r.y.x + l.y.x * r.y.y + l.z.x * r.y.z,
                .y = l.x.y * r.y.x + l.y.y * r.y.y + l.z.y * r.y.z,
                .z = l.x.z * r.y.x + l.y.z * r.y.y + l.z.z * r.y.z,
            },
            .z = Vec3{
                .x = l.x.x * r.z.x + l.y.x * r.z.y + l.z.x * r.z.z,
                .y = l.x.y * r.z.x + l.y.y * r.z.y + l.z.y * r.z.z,
                .z = l.x.z * r.z.x + l.y.z * r.z.y + l.z.z * r.z.z,
            },
            .w = Vec3{
                .x = l.x.x * r.w.x + l.y.x * r.w.y + l.z.x * r.w.z + l.w.x,
                .y = l.x.y * r.w.x + l.y.y * r.w.y + l.z.y * r.w.z + l.w.y,
                .z = l.x.z * r.w.x + l.y.z * r.w.y + l.z.z * r.w.z + l.w.z,
            },
        };
    }

    pub fn mulMat4Mat4x3(l: var, r: var) Mat4 {
        return Mat4{
            .x = Vec4{
                .x = l.x.x * r.x.x + l.y.x * r.x.y + l.z.x * r.x.z,
                .y = l.x.y * r.x.x + l.y.y * r.x.y + l.z.y * r.x.z,
                .z = l.x.z * r.x.x + l.y.z * r.x.y + l.z.z * r.x.z,
                .w = l.x.w * r.x.x + l.y.w * r.x.y + l.z.w * r.x.z,
            },
            .y = Vec4{
                .x = l.x.x * r.y.x + l.y.x * r.y.y + l.z.x * r.y.z,
                .y = l.x.y * r.y.x + l.y.y * r.y.y + l.z.y * r.y.z,
                .z = l.x.z * r.y.x + l.y.z * r.y.y + l.z.z * r.y.z,
                .w = l.x.w * r.y.x + l.y.w * r.y.y + l.z.w * r.y.z,
            },
            .z = Vec4{
                .x = l.x.x * r.z.x + l.y.x * r.z.y + l.z.x * r.z.z,
                .y = l.x.y * r.z.x + l.y.y * r.z.y + l.z.y * r.z.z,
                .z = l.x.z * r.z.x + l.y.z * r.z.y + l.z.z * r.z.z,
                .w = l.x.w * r.z.x + l.y.w * r.z.y + l.z.w * r.z.z,
            },
            .w = Vec4{
                .x = l.w.x * r.w.x + l.y.x * r.w.y + l.z.x * r.w.z + l.w.x,
                .y = l.w.y * r.w.x + l.y.y * r.w.y + l.z.y * r.w.z + l.w.y,
                .z = l.w.z * r.w.x + l.y.z * r.w.y + l.z.z * r.w.z + l.w.z,
                .w = l.w.w * r.w.x + l.y.w * r.w.y + l.z.w * r.w.z + l.w.w,
            },
        };
    }

    pub fn mulMat4x3Mat4(l: var, r: var) Mat4 {
        return Mat4{
            .x = Vec4{
                .x = l.x.x * r.x.x + l.y.x * r.x.y + l.z.x * r.x.z + l.w.x * r.x.w,
                .y = l.x.y * r.x.x + l.y.y * r.x.y + l.z.y * r.x.z + l.w.y * r.x.w,
                .z = l.x.z * r.x.x + l.y.z * r.x.y + l.z.z * r.x.z + l.w.z * r.x.w,
                .w = r.x.w,
            },
            .y = Vec4{
                .x = l.x.x * r.y.x + l.y.x * r.y.y + l.z.x * r.y.z + l.w.x * r.y.w,
                .y = l.x.y * r.y.x + l.y.y * r.y.y + l.z.y * r.y.z + l.w.y * r.y.w,
                .z = l.x.z * r.y.x + l.y.z * r.y.y + l.z.z * r.y.z + l.w.z * r.y.w,
                .w = r.y.w,
            },
            .z = Vec4{
                .x = l.x.x * r.z.x + l.y.x * r.z.y + l.z.x * r.z.z + l.w.x * r.z.w,
                .y = l.x.y * r.z.x + l.y.y * r.z.y + l.z.y * r.z.z + l.w.y * r.z.w,
                .z = l.x.z * r.z.x + l.y.z * r.z.y + l.z.z * r.z.z + l.w.z * r.z.w,
                .w = r.z.w,
            },
            .w = Vec4{
                .x = l.x.x * r.w.x + l.y.x * r.w.y + l.z.x * r.w.z + l.w.x * r.w.w,
                .y = l.x.y * r.w.x + l.y.y * r.w.y + l.z.y * r.w.z + l.w.y * r.w.w,
                .z = l.x.z * r.w.x + l.y.z * r.w.y + l.z.z * r.w.z + l.w.z * r.w.w,
                .w = r.w.w,
            },
        };
    }

    pub fn mulMat4Mat4(l: var, r: var) Mat4 {
        return Mat4{
            .x = Vec4{
                .x = l.x.x * r.x.x + l.y.x * r.x.y + l.z.x * r.x.z + l.w.x * r.x.w,
                .y = l.x.y * r.x.x + l.y.y * r.x.y + l.z.y * r.x.z + l.w.y * r.x.w,
                .z = l.x.z * r.x.x + l.y.z * r.x.y + l.z.z * r.x.z + l.w.z * r.x.w,
                .w = l.x.w * r.x.x + l.y.w * r.x.y + l.z.w * r.x.z + l.w.w * r.x.w,
            },
            .y = Vec4{
                .x = l.x.x * r.y.x + l.y.x * r.y.y + l.z.x * r.y.z + l.w.x * r.y.w,
                .y = l.x.y * r.y.x + l.y.y * r.y.y + l.z.y * r.y.z + l.w.y * r.y.w,
                .z = l.x.z * r.y.x + l.y.z * r.y.y + l.z.z * r.y.z + l.w.z * r.y.w,
                .w = l.x.w * r.y.x + l.y.w * r.y.y + l.z.w * r.y.z + l.w.w * r.y.w,
            },
            .z = Vec4{
                .x = l.x.x * r.z.x + l.y.x * r.z.y + l.z.x * r.z.z + l.w.x * r.z.w,
                .y = l.x.y * r.z.x + l.y.y * r.z.y + l.z.y * r.z.z + l.w.y * r.z.w,
                .z = l.x.z * r.z.x + l.y.z * r.z.y + l.z.z * r.z.z + l.w.z * r.z.w,
                .w = l.x.w * r.z.x + l.y.w * r.z.y + l.z.w * r.z.z + l.w.w * r.z.w,
            },
            .w = Vec4{
                .x = l.x.x * r.w.x + l.y.x * r.w.y + l.z.x * r.w.z + l.w.x * r.w.w,
                .y = l.x.y * r.w.x + l.y.y * r.w.y + l.z.y * r.w.z + l.w.y * r.w.w,
                .z = l.x.z * r.w.x + l.y.z * r.w.y + l.z.z * r.w.z + l.w.z * r.w.w,
                .w = l.x.w * r.w.x + l.y.w * r.w.y + l.z.w * r.w.z + l.w.w * r.w.w,
            },
        };
    }

    pub fn preScaleMat3Vec(l: var, r: Vec3) Mat3 {
        return Mat3{
            .x = Vec3.init(l.x.x, l.x.y, l.x.z).scale(r.x),
            .y = Vec3.init(l.y.x, l.y.y, l.z.z).scale(r.y),
            .z = Vec3.init(l.z.x, l.z.y, l.z.z).scale(r.z),
        };
    }

    pub fn postScaleMat3Vec(l: var, r: Vec3) Mat3 {
        return Mat3{
            .x = Vec3.init(l.x.x, l.x.y, l.x.z).mul(r),
            .y = Vec3.init(l.y.x, l.y.y, l.z.z).mul(r),
            .z = Vec3.init(l.z.x, l.z.y, l.z.z).mul(r),
        };
    }

    pub fn postRotateMat3(l: var, r: Rotor3) Mat3 {
        return Mat3{
            .x = @inlineCall(Rotor3.apply, r, Vec3.init(l.x.x, l.x.y, l.x.z)),
            .y = @inlineCall(Rotor3.apply, r, Vec3.init(l.y.x, l.y.y, l.y.z)),
            .z = @inlineCall(Rotor3.apply, r, Vec3.init(l.z.x, l.z.y, l.z.z)),
        };
    }

    pub fn postRotateMat4x3(l: var, r: Rotor3) Mat4x3 {
        var result: Mat4x3 = undefined;
        setMat3(&result, postRotateMat3(l, r));
        result.w = Vec3.init(l.w.x, l.w.y, l.w.z);
        return result;
    }

    pub fn preRotateMat3(l: var, r: Rotor3) Mat3 {
        return mulMat3Mat3(l, r.toMat3());
    }

    pub fn preRotateMat4x3(l: var, r: Rotor3) Mat4x3 {
        return mulMat4x3Mat3(l, r.toMat3());
    }

    pub inline fn setMat3(dest: var, src: var) void {
        dest.x.x = src.x.x;
        dest.x.y = src.x.y;
        dest.x.z = src.x.z;
        dest.y.x = src.y.x;
        dest.y.y = src.y.y;
        dest.y.z = src.y.z;
        dest.z.x = src.z.x;
        dest.z.y = src.z.y;
        dest.z.z = src.z.z;
    }

    pub inline fn setMat4x3(dest: var, src: var) void {
        dest.x.x = src.x.x;
        dest.x.y = src.x.y;
        dest.x.z = src.x.z;
        dest.y.x = src.y.x;
        dest.y.y = src.y.y;
        dest.y.z = src.y.z;
        dest.z.x = src.z.x;
        dest.z.y = src.z.y;
        dest.z.z = src.z.z;
        dest.w.x = src.w.x;
        dest.w.y = src.w.y;
        dest.w.z = src.w.z;
    }

    pub inline fn extractPreScale3NoFlip(m: var) Vec3 {
        return Vec3{
            .x = Vec3.init(m.x.x, m.x.y, m.x.z).len(),
            .y = Vec3.init(m.y.x, m.y.y, m.y.z).len(),
            .z = Vec3.init(m.z.x, m.z.y, m.z.z).len(),
        };
    }

    pub inline fn extractPreScale3(m: var) Vec3 {
        var scale = extractPreScale3NoFlip(m);
        scale.x = math.copysign(determinant3x3(m), scale.x);
    }

    pub fn extractTransform3x3(m: var) Transform3 {
        var scale = extractPreScale3NoFlip(m);
        const invScale = Vec3.init(1 / scale.x, 1 / scale.y, 1 / scale.z);
        var unit = postScaleMat3Vec(m, invScale);
        const det = determinant3x3(unit);

        // If the determinant is not approx 1, this matrix has shear and
        // we cannot decompose it.
        assert(math.approxEq(f32, 1, math.fabs(det), 1e-4));

        if (det < 0) {
            // this matrix inverts chirality.  Flip a scale and one of the matrix bases.
            scale.x = -scale.x;
            unit.x = unit.x.negate();
        }

        return Transform3{
            .rotation = Rotor3.fromMatrix(unit),
            .translation = Vec3.Zero,
            .scale = scale,
        };
    }

    pub fn extractTransform4x3(m: var) Transform3 {
        var scale = extractPreScale3NoFlip(m);
        const invScale = Vec3.init(1 / scale.x, 1 / scale.y, 1 / scale.z);
        var unit = postScaleMat3Vec(m, invScale);
        const det = determinant3x3(unit);

        // If the determinant is not approx 1, this matrix has shear and
        // we cannot decompose it.
        assert(math.approxEq(f32, 1, math.fabs(det), 1e-4));

        if (det < 0) {
            // this matrix inverts chirality.  Flip a scale and one of the matrix bases.
            scale.x = -scale.x;
            unit.x = unit.x.negate();
        }

        return Transform3{
            .rotation = Rotor3.fromMatrix(unit),
            .translation = Vec3.init(m.w.x, m.w.y, m.w.z),
            .scale = scale,
        };
    }
};

test "compile Mat3" {
    var a = Mat3.Identity;
    var b = a;
    _ = a.row(0);
    _ = a.row(1);
    _ = a.row(2);
    _ = a.col(0);
    _ = a.col(1);
    _ = a.col(2);
    _ = a.preScaleVec(Vec3.X);
    _ = a.postScaleVec(Vec3.Y);
    _ = a.scale(4);
    _ = a.preRotate(Rotor3.Identity);
    _ = a.postRotate(Rotor3.Identity);
    _ = a.mulVec(Vec3.Z);
    _ = a.transpose();
    _ = a.determinant();
    _ = try a.inverse();
    _ = try a.transposedInverse();
    _ = a.mulMat(b);
    _ = a.mulMat4x3(Mat4x3.Identity);
    _ = a.mulMat4(Mat4.Identity);
    _ = a.asBuf();
    _ = a.asGrid();
    _ = a.toMat4x3(Vec3.Zero);
    _ = a.toMat4(Vec3.Zero);
    _ = a.toMat4Projection(Vec3.Zero, Vec4.W);
}

test "compile Mat4x3" {
    var a = Mat4x3.Identity;
    var b = a;
    _ = a.row(0);
    _ = a.row(1);
    _ = a.row(2);
    _ = a.col(0);
    _ = a.col(1);
    _ = a.col(2);
    _ = a.col(3);
    _ = a.preScaleVec(Vec3.X);
    _ = a.postScaleVec(Vec3.Y);
    _ = a.preScale(4);
    _ = a.postScale(0.25);
    _ = a.preTranslate(Vec3.X);
    _ = a.postTranslate(Vec3.Y);
    _ = a.preRotate(Rotor3.Identity);
    _ = a.postRotate(Rotor3.Identity);
    _ = a.mul3x3Vec(Vec3.Z);
    _ = a.mulVec3(Vec3.X);
    _ = a.mulVec(Vec4.W);
    _ = try a.inverse();
    _ = a.mulMat3(Mat3.Identity);
    _ = a.mulMat(b);
    _ = a.mulMat4(Mat4.Identity);
    _ = a.asBuf();
    _ = a.asGrid();
    _ = a.asMat3();
    _ = a.toMat3();
    _ = a.toMat4();
    _ = a.toMat4Projection(Vec4.W);
}

test "compile Mat4" {
    var a = Mat4.Identity;
    var b = a;
    _ = a.row(0);
    _ = a.row(1);
    _ = a.row(2);
    _ = a.row(3);
    _ = a.col(0);
    _ = a.col(1);
    _ = a.col(2);
    _ = a.col(3);
    _ = a.preScaleVec(Vec3.X);
    _ = a.postScaleVec(Vec3.Y);
    _ = a.preScale(4);
    _ = a.postScale(0.25);
    _ = a.preTranslate(Vec3.Y);
    _ = a.postTranslate(Vec3.Z);
    _ = a.project(Vec3.X);
    _ = a.mulVec(Vec4.W);
    _ = a.mulMat3(Mat3.Identity);
    _ = a.mulMat4x3(Mat4x3.Identity);
    _ = a.mulMat(b);
    _ = a.asBuf();
    _ = a.asGrid();
    _ = a.toMat3();
    _ = a.toMat4x3();
}
