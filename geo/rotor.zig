const std = @import("std");
const math = std.math;
const testing = std.testing;

const vecs = @import("vec.zig");
const Vec2 = vecs.Vec2;
const Vec3 = vecs.Vec3;
const Vec4 = vecs.Vec4;
const BiVec3 = vecs.BiVec3;

const mats = @import("mat.zig");
const Mat3 = mats.Mat3;

pub const Rotor2 = extern struct {
    dot: f32,
    wedge: f32,

    /// A rotor that rotates 0 degrees
    pub const Identity = Rotor2{ .dot = 1, .wedge = 0 };

    /// Constructs a rotor that rotates counter-clockwise
    /// around the origin by the given angle.
    pub inline fn initAngle(angleRad: f32) Rotor2 {
        return Rotor2{
            .dot = math.cos(angleRad),
            .wedge = math.sin(angleRad),
        };
    }

    /// Constructs a rotor that, if applied to a, would produce b.
    /// a and b must be normalized.
    pub inline fn diffNormalized(a: Vec2, b: Vec2) Rotor2 {
        return Rotor2{
            .dot = a.dot(b),
            .wedge = a.wedge(b),
        };
    }

    /// Constructs a rotor that rotates a to the direction of b.
    /// a and b are assumed not to be normalized.
    /// Returns error.Singular if a or b are near zero.
    pub inline fn diff(a: Vec2, b: Vec2) !Rotor2 {
        return try (Rotor2{
            .dot = a.dot(b),
            .wedge = a.wedge(b),
        }).normalize();
    }

    /// Rotates vec around the origin
    pub inline fn apply(self: Rotor2, vec: Vec2) Vec2 {
        return Vec2{
            .x = vec.x * self.dot - vec.y * self.wedge,
            .y = vec.x * self.wedge + vec.y * self.dot,
        };
    }

    /// Creates a rotor that rotates the same amount in the opposite direction
    pub inline fn reverse(self: Rotor2) Rotor2 {
        return Rotor2{
            .dot = self.dot,
            .wedge = -self.wedge,
        };
    }

    /// Combines two rotors into one
    pub inline fn add(a: Rotor2, b: Rotor2) Rotor2 {
        return Rotor2{
            .dot = a.dot * b.dot - a.wedge * b.wedge,
            .wedge = a.dot * b.wedge + a.wedge * b.dot,
        };
    }

    /// Adds 90 degrees counterclockwise to the rotation
    pub inline fn addLeft(self: Rotor2) Rotor2 {
        return Rotor2{
            .dot = -self.wedge,
            .wedge = self.dot,
        };
    }

    /// Adds 180 degrees to the rotation
    pub inline fn addHalf(self: Rotor2) Rotor2 {
        return Rotor2{
            .dot = -self.dot,
            .wedge = -self.wedge,
        };
    }

    /// Adds 90 degrees clockwise to the rotation
    pub inline fn addRight(self: Rotor2) Rotor2 {
        return Rotor2{
            .dot = self.wedge,
            .wedge = -self.dot,
        };
    }

    /// Normalizes the rotor to unit length.
    /// Rotors should stay normalized most of the time.
    /// Normalizing the zero rotor will result in error.Singular.
    pub inline fn normalize(self: Rotor2) !Rotor2 {
        var v2 = Vec2.init(self.dot, self.wedge);
        v2 = try v2.normalize();
        return Rotor2{
            .dot = v2.x,
            .wedge = v2.y,
        };
    }

    /// Calculates the angle that this rotor rotates in the counterclockwise direction
    pub inline fn toAngleRad(self: Rotor2) f32 {
        return math.atan2(f32, self.wedge, self.dot);
    }
};

pub const Rotor3 = extern struct {
    /// The dot product of the two rotor vectors.
    pub dot: f32,

    /// The wedge product of the two rotor vectors.
    /// This is the plane in which the rotor rotates.
    pub wedge: BiVec3,

    /// The rotor that performs no rotation
    pub const Identity = Rotor3{ .dot = 1.0, .wedge = BiVec3.Zero };

    /// Creates a rotor that reflects across two unit vectors.
    /// The parameters must both be unit vectors, or a.len() * b.len() must equal 1.
    /// The rotor will rotate in the plane of ab from a towards b,
    /// for double the angle between ab.
    pub fn initVecsNormalized(a: Vec3, b: Vec3) Rotor3 {
        return (Rotor3{
            .dot = b.dot(a),
            .wedge = b.wedge(a),
        }).standardize();
    }

    /// Creates a rotor that reflects across two vectors.
    /// The rotor will rotate in the plane of ab from a towards b,
    /// for double the angle between ab.
    /// If a or b is zero, returns error.Singular.
    pub fn initVecs(a: Vec3, b: Vec3) !Rotor3 {
        return try (Rotor3{
            .dot = b.dot(a),
            .wedge = b.wedge(a),
        }).standardize().normalize();
    }

    /// Creates a rotor that rotates a to b along the plane between a and b
    /// If a and b are 180 degrees apart, picks an arbitrary axis to rotate around.
    /// If a or b is zero, returns error.Singular.
    pub fn diffVec(a: Vec3, b: Vec3) !Rotor3 {
        const normAB = math.sqrt(a.lenSquared() * b.lenSquared());
        return (Rotor3{
            .dot = b.dot(a) + normAB,
            .wedge = b.wedge(a),
        }).normalize() catch Rotor3{
            .dot = 0,
            .wedge = try a.orthogonal().toBiVec3().normalize(),
        };
    }

    /// Creates a rotor that rotates a to b along the plane between a and b
    /// If a and b are 180 degrees apart, picks an arbitrary axis to rotate around.
    /// If any input vector is zero, returns error.Singular.
    pub fn diffVecPreferredOrtho(a: Vec3, b: Vec3, ortho: BiVec3) !Rotor3 {
        const normAB = math.sqrt(a.lenSquared() * b.lenSquared());
        return (Rotor3{
            .dot = b.dot(a) + normAB,
            .wedge = b.wedge(a),
        }).normalize() catch Rotor3{
            .dot = 0,
            .wedge = try ortho.normalize(),
        };
    }

    /// Creates a rotor that performs half of the rotation of this one.
    pub fn halfway(self: Rotor3) Rotor3 {
        return (Rotor3{
            .dot = self.dot + 1.0,
            .wedge = self.wedge,
        }).normalize() catch unreachable;
    }

    /// Creates a rotor that rotates from to to, and changes the up direction from fromUp to toUp.
    /// Returns error.Singular if:
    ///  - any input vector is zero
    ///  - from cross fromUp is zero
    ///  - to cross toUp is zero
    pub fn diffFrame(from: Vec3, fromUp: Vec3, to: Vec3, toUp: Vec3) !Rotor3 {
        // get vectors perpendicular to from and to
        const fromOut = from.cross(fromUp);
        const toOut = to.cross(toUp);
        // calculate the rotor that turns from to to
        const baseRotor = diffVec(from, to);
        // apply that rotation to the fromOut.
        // rotatedFromOut is perpendicular to to.
        const rotatedFromOut = baseRotor.apply(fromOut);
        // make a second rotor that rotates around to
        // this fixes up the up vector
        const fixUpRotor = diffVecPreferredOrtho(rotatedFromOut, toOut, to.toBiVec3());
        // combine the two into a single rotor
        return fixUpRotor.preMul(baseRotor);
    }

    /// Calculates the rotor that transforms a to b.
    /// diff(a, b)(a(x)) == b(x).
    pub fn diff(a: Rotor3, b: Rotor3) Rotor3 {
        return b.preMul(a.reverse());
    }

    /// Creates a rotor on a given wedge for a given angle.
    pub fn axisAngle(axis: BiVec3, angle: f32) !Rotor3 {
        return axisAngleNormalized(try axis.normalize(), angle);
    }

    /// Creates a rotor on a given wedge for a given angle.
    /// The wedge must be normalized.
    pub fn axisAngleNormalized(axis: BiVec3, angle: f32) Rotor3 {
        const cos = math.cos(angle * 0.5);
        const sin = math.sin(angle * 0.5);
        return (Rotor3{
            .dot = cos,
            .wedge = axis.scale(sin),
        }).standardize();
    }

    /// Creates a rotor around the x axis.
    /// angle is in radians.
    pub fn aroundX(angle: f32) Rotor3 {
        const cos = math.cos(angle * 0.5);
        const sin = math.sin(angle * 0.5);
        return (Rotor3{
            .dot = cos,
            .wedge = BiVec3{
                .yz = sin,
                .zx = 0,
                .xy = 0,
            },
        }).standardize();
    }

    /// Creates a rotor around the y axis.
    /// angle is in radians.
    pub fn aroundY(angle: f32) Rotor3 {
        const cos = math.cos(angle * 0.5);
        const sin = math.sin(angle * 0.5);
        return (Rotor3{
            .dot = cos,
            .wedge = BiVec3{
                .yz = 0,
                .zx = sin,
                .xy = 0,
            },
        }).standardize();
    }

    /// Creates a rotor around the z axis.
    /// angle is in radians.
    pub fn aroundZ(angle: f32) Rotor3 {
        const cos = math.cos(angle * 0.5);
        const sin = math.sin(angle * 0.5);
        return (Rotor3{
            .dot = cos,
            .wedge = BiVec3{
                .yz = 0,
                .zx = 0,
                .xy = sin,
            },
        }).standardize();
    }

    /// Translates the quaternion w + xi + yj + zk into a Rotor.
    /// Assumes that the quaternion is normalized.  If it is not,
    /// normalize() must be called afterwards.
    pub fn fromQuaternion(w: f32, x: f32, y: f32, z: f32) Rotor3 {
        return (Rotor3{
            .dot = w,
            .wedge = BiVec3{
                .yz = y,
                .zx = -z, // quaternions effectively use xz, and zx = -xz
                .xy = x,
            },
        }).standardize();
    }

    /// Normalizes the rotor to unit length.
    /// Rotors should stay normalized most of the time.
    pub fn normalize(self: Rotor3) !Rotor3 {
        const v4 = @bitCast(Vec4, self);
        const norm = try v4.normalize();
        return @bitCast(Rotor3, norm);
    }

    /// Standardizes the rotor to avoid double-cover.
    /// A standardized rotor has the property that its first
    /// non-zero component is positive.
    pub fn standardize(self: Rotor3) Rotor3 {
        if (self.dot > 0) return self;
        return Rotor3{
            .dot = -self.dot,
            .wedge = BiVec3{
                .yz = -self.wedge.yz,
                .zx = -self.wedge.zx,
                .xy = -self.wedge.xy,
            },
        };
    }

    /// Composes two rotors into one that applies b first then a.
    pub fn preMul(a: Rotor3, b: Rotor3) Rotor3 {
        // TODO make sure this is the correct direction.
        return Rotor3{
            .dot = a.dot * b.dot + a.wedge.dot(b.wedge),
            .wedge = a.wedge.scale(b.dot).add(b.wedge.scale(a.dot)).add(a.wedge.wedge(b.wedge)),
        };
    }

    /// Interpolates evenly between two rotors along the shortest path.
    /// If one parameter is standardized and the other is not, will interpolate
    /// on the longest path instead.
    pub fn slerp(self: Rotor3, target: Rotor3, alpha: f32) Rotor3 {
        const va = @bitCast(Vec4, self);
        const vb = @bitCast(Vec4, target);
        const cosAngle = va.dot(vb);
        if (math.fabs(cosAngle) > 0.999) return self.nlerp(target, alpha) catch unreachable;
        const angle = math.acos(cosAngle);
        const scale = 1.0 / math.sin(angle);
        const fromMult = math.sin((1.0 - alpha) * angle) * scale;
        const toMult = math.sin(alpha * angle) * scale;
        const blended = va.scale(fromMult).add(vb.scale(toMult));
        return @bitCast(Rotor3, blended);
    }

    /// Interpolates between two rotors, but is slightly faster in the
    /// middle and slower on each end.  Useful for rotors that are close
    /// to each other where this effect is not noticeable.
    pub fn nlerp(self: Rotor3, target: Rotor3, alpha: f32) !Rotor3 {
        const a = @bitCast(Vec4, self);
        const b = @bitCast(Vec4, target);
        const lerped = a.lerp(b, alpha);
        const norm = try lerped.normalize();
        return @bitCast(Rotor3, norm);
    }

    /// Rotates a vector
    pub fn apply(self: Rotor3, in: Vec3) Vec3 {
        // compute all distributive products
        const dot2 = self.dot * self.dot;
        const yz2 = self.wedge.yz * self.wedge.yz;
        const zx2 = self.wedge.zx * self.wedge.zx;
        const xy2 = self.wedge.xy * self.wedge.xy;
        // multiply these by 2 since they are always used in pairs
        const dotyz = self.dot * self.wedge.yz * 2;
        const dotzx = self.dot * self.wedge.zx * 2;
        const dotxy = self.dot * self.wedge.xy * 2;
        const yzzx = self.wedge.yz * self.wedge.zx * 2;
        const zxxy = self.wedge.zx * self.wedge.xy * 2;
        const xyyz = self.wedge.xy * self.wedge.yz * 2;

        // calculate the rotated components
        const x = (dot2 + yz2 - zx2 - xy2) * in.x + (yzzx - dotxy) * in.y + (xyyz + dotzx) * in.z;
        const y = (dot2 - yz2 + zx2 - xy2) * in.y + (zxxy - dotyz) * in.z + (yzzx + dotxy) * in.x;
        const z = (dot2 - yz2 - zx2 + xy2) * in.z + (xyyz - dotzx) * in.x + (zxxy + dotyz) * in.y;

        return Vec3.init(x, y, z);
    }

    /// Creates a Mat3 that performs the same transform as this rotor
    pub fn toMat3(self: Rotor3) Mat3 {
        // compute all distributive products
        const dot2 = self.dot * self.dot;
        const yz2 = self.wedge.yz * self.wedge.yz;
        const zx2 = self.wedge.zx * self.wedge.zx;
        const xy2 = self.wedge.xy * self.wedge.xy;
        // multiply these by 2 since they are always used in pairs
        const dotyz = self.dot * self.wedge.yz * 2;
        const dotzx = self.dot * self.wedge.zx * 2;
        const dotxy = self.dot * self.wedge.xy * 2;
        const yzzx = self.wedge.yz * self.wedge.zx * 2;
        const zxxy = self.wedge.zx * self.wedge.xy * 2;
        const xyyz = self.wedge.xy * self.wedge.yz * 2;

        return Mat3{
            .x = Vec3{
                .x = dot2 + yz2 - zx2 - xy2,
                .y = yzzx + dotxy,
                .z = xyyz - dotzx,
            },
            .y = Vec3{
                .x = yzzx - dotxy,
                .y = dot2 - yz2 + zx2 - xy2,
                .z = zxxy + dotyz,
            },
            .z = Vec3{
                .x = xyyz + dotzx,
                .y = zxxy - dotyz,
                .z = dot2 - yz2 - zx2 + xy2,
            },
        };
    }

    /// Calculates the axis of rotation as a unit vector
    pub inline fn calcRotationAxis(self: Rotor3) !BiVec3 {
        const mult = 1.0 / math.sqrt(math.max(0.0, 1.0 - self.dot * self.dot));
        if (!math.isFinite(mult)) return error.Singular;
        return self.wedge.scale(mult);
    }

    /// Calculates the angle of rotation
    pub inline fn calcRotationAngle(self: Rotor3) f32 {
        return math.acos(self.dot);
    }
};

test "compile Rotor2" {
    var x = Vec2.X;
    var y = Vec2.Y;
    var a = Rotor2.initAngle(32);
    var b = try Rotor2.diff(x, y);
    _ = Rotor2.diffNormalized(x, y);
    _ = a.apply(x);
    _ = a.reverse();
    _ = a.add(b);
    _ = a.addLeft();
    _ = a.addHalf();
    _ = a.addRight();
    _ = try a.normalize();
    _ = a.toAngleRad();
}

test "compile Rotor3" {
    var a = Rotor3.Identity;
    var b = Rotor3.fromQuaternion(0, 1, 0, 0);
    var c = try b.normalize();
    _ = b.standardize();
    _ = b.preMul(c);
    _ = a.slerp(b, 0.25);
    _ = try a.nlerp(c, 0.25);
    _ = a.apply(Vec3.X);
}
