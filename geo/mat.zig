const std = @import("std");

usingnamespace @import("vec.zig");

/// A 3x3 matrix.  When required to choose, this library uses
/// the column-major convention.
pub const Mat3 = extern struct {
    pub x: Vec3,
    pub y: Vec3,
    pub z: Vec3,

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

    /// Constructs a Mat4 with this matrix as the rotation/scale part,
    pub inline fn toMat4(self: Mat3, translation: Vec3, projection: Vec4) Mat4x3 {
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

    /// Constructs a Mat4 with this matrix as the rotation/scale part,
    pub inline fn toMat4(self: Mat3, projection: Vec4) Mat4x3 {
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
};
