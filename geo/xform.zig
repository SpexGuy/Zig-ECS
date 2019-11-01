const std = @import("std");

const vecs = @import("vec.zig");
const Vec2 = vecs.Vec2;
const Vec3 = vecs.Vec3;
const Vec4 = vecs.Vec4;

const mats = @import("mat.zig");
const Mat3 = mats.Mat3;
const Mat4x3 = mats.Mat4x3;
const Mat4 = mats.Mat4;

const rotors = @import("rotor.zig");
const Rotor2 = rotors.Rotor2;
const Rotor3 = rotors.Rotor3;

pub const Transform2 = struct {
    pub rotation: Rotor2,
    pub translation: Vec2,
    pub scale: Vec2,
};

pub const Transform3 = struct {
    pub rotation: Rotor3,
    pub translation: Vec3,
    pub scale: Vec3,

    pub fn toMat3(self: Transform3) Mat3x3 {
        return self.rotation.toMat3().preScaleVec(self.scale);
    }

    pub fn toMat4x3(self: Transform3) Mat4x3 {
        return self.toMat3().toMat4x3(self.translation);
    }

    pub fn apply(self: Transform3, point: Vec3) Vec3 {
        return self.rotation.apply(point.mul(self.scale)).add(self.translation);
    }
};
