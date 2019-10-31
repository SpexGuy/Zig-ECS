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

    pub fn init(dot: f32, yz: f32, zx: f32, xy: f32) Rotor3 {
        return Rotor3{
            .dot = dot,
            .wedge = BiVec3{
                .yz = yz,
                .zx = zx,
                .xy = xy,
            },
        };
    }

    /// Creates a rotor that reflects across two unit vectors.
    /// The parameters must both be unit vectors, or a.len() * b.len() must equal 1.
    /// The rotor will rotate in the plane of ab from a towards b,
    /// for double the angle between ab.
    pub fn initVecsNormalized(a: Vec3, b: Vec3) Rotor3 {
        return (Rotor3{
            .dot = a.dot(b),
            .wedge = a.wedge(b),
        }).standardize();
    }

    /// Creates a rotor that reflects across two vectors.
    /// The rotor will rotate in the plane of ab from a towards b,
    /// for double the angle between ab.
    /// If a or b is zero, returns error.Singular.
    pub fn initVecs(a: Vec3, b: Vec3) !Rotor3 {
        return try (Rotor3{
            .dot = a.dot(b),
            .wedge = a.wedge(b),
        }).standardize().normalize();
    }

    /// Creates a rotor that rotates a to b along the plane between a and b
    /// If a and b are 180 degrees apart, picks an arbitrary axis to rotate around.
    /// If a or b is zero, returns error.Singular.
    pub fn diffVec(a: Vec3, b: Vec3) !Rotor3 {
        const normAB = math.sqrt(a.lenSquared() * b.lenSquared());
        return (Rotor3{
            .dot = a.dot(b) + normAB,
            .wedge = a.wedge(b),
        }).normalize() catch Rotor3{
            .dot = 0,
            .wedge = try a.orthogonal().toBiVec3().normalize(),
        };
    }

    /// Creates a rotor that rotates along the ortho plane from a's projection to b's projection.
    /// The returned rotor is guaranteed to rotate in the direction of ortho, and as a result
    /// it may not be standardized.  Call standardize() on the result if you want the shorter rotation.
    pub fn diffVecAlong(a: Vec3, b: Vec3, ortho: BiVec3) !Rotor3 {
        // get projection of a and b onto ortho.  They will be rotated 90 degrees since we
        // are using dotVec but it doesn't matter since we only care about the angle between them.
        const aPerp = ortho.dotVec(a);
        const bPerp = ortho.dotVec(b);

        const normAB2 = aPerp.lenSquared() * bPerp.lenSquared();
        const normAB = math.sqrt(normAB2);
        const dot = aPerp.dot(bPerp);
        const crossMag = math.sqrt(normAB2 - dot * dot);
        const normOrtho = try ortho.normalize();

        return (Rotor3{
            .dot = dot + normAB,
            .wedge = normOrtho.scale(crossMag),
        }).normalize() catch
            if (normAB == 0) error.Singular else Rotor3{
            .dot = 0,
            .wedge = normOrtho,
        };
    }

    /// Creates a rotor that performs half of the rotation of this one.
    pub fn halfway(self: Rotor3) Rotor3 {
        return (Rotor3{
            .dot = self.dot + 1.0,
            .wedge = self.wedge,
        }).normalize() catch Rotor3.Identity;
    }

    /// Creates a rotor that rotates from to to, and changes the up direction from fromUp to toUp.
    /// Returns error.Singular if:
    ///  - any input vector is zero
    ///  - from cross fromUp is zero
    ///  - to cross toUp is zero
    pub fn diffFrame(from: Vec3, fromUp: Vec3, to: Vec3, toUp: Vec3) !Rotor3 {
        // calculate the rotor that turns from to to
        const baseRotor = try diffVec(from, to);
        // apply that rotation to the fromOut.
        // rotatedFromOut is perpendicular to to.
        const rotatedFromUp = baseRotor.apply(fromUp);
        // make a second rotor that rotates around to
        // this fixes up the up vector
        const fixUpRotor = (try diffVecAlong(rotatedFromUp, toUp, to.toBiVec3())).standardize();
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
    /// Assumes the identities i*j = k, j*k = i, k*i = j, ijk = -1
    pub fn fromQuaternion(w: f32, x: f32, y: f32, z: f32) Rotor3 {
        return (Rotor3{
            .dot = w,
            .wedge = BiVec3{
                .yz = -x,
                .zx = -y,
                .xy = -z,
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
        if (self.dot >= -0.0) return self;
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
        return Rotor3{
            .dot = a.dot * b.dot + b.wedge.dot(a.wedge),
            .wedge = b.wedge.scale(a.dot).add(a.wedge.scale(b.dot)).add(b.wedge.wedge(a.wedge)),
        };
    }

    /// Returns a rotor that rotates the same amount in the opposite direction.
    pub fn reverse(r: Rotor3) Rotor3 {
        return Rotor3{
            .dot = r.dot,
            .wedge = r.wedge.negate(),
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

    pub fn expectNear(expected: Rotor3, actual: Rotor3, epsilon: f32) void {
        if (!math.approxEq(f32, expected.dot, actual.dot, epsilon) or
            !math.approxEq(f32, expected.wedge.yz, actual.wedge.yz, epsilon) or
            !math.approxEq(f32, expected.wedge.zx, actual.wedge.zx, epsilon) or
            !math.approxEq(f32, expected.wedge.xy, actual.wedge.xy, epsilon))
        {
            std.debug.panic(
                "Expected Rotor3({}, ({}, {}, {})), found Rotor3({}, ({}, {}, {}))",
                expected.dot,
                expected.wedge.yz,
                expected.wedge.zx,
                expected.wedge.xy,
                actual.dot,
                actual.wedge.yz,
                actual.wedge.zx,
                actual.wedge.xy,
            );
        }
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

test "Rotor3.initVecs" {
    const epsilon = 1e-5;
    const Identity = Rotor3.Identity;
    const expectNear = Rotor3.expectNear;
    expectNear(Identity, try Rotor3.initVecs(Vec3.X, Vec3.X), epsilon);
    expectNear(Identity, try Rotor3.initVecs(Vec3.Y, Vec3.Y), epsilon);
    expectNear(Identity, try Rotor3.initVecs(Vec3.Z, Vec3.Z), epsilon);
    expectNear(Rotor3.init(0, 0, 0, 1), try Rotor3.initVecs(Vec3.X, Vec3.Y), epsilon);
    expectNear(Rotor3.init(0, 0, -1, 0), try Rotor3.initVecs(Vec3.X, Vec3.Z), epsilon);
    expectNear(Rotor3.init(0, 0, 1, 0), try Rotor3.initVecs(Vec3.Z, Vec3.X), epsilon);
    expectNear(Rotor3.init(0, 1, 0, 0), try Rotor3.initVecs(Vec3.Y, Vec3.Z), epsilon);

    const isqrt2 = 1.0 / math.sqrt(2.0);
    expectNear(Rotor3.init(isqrt2, 0, 0, isqrt2), try Rotor3.initVecs(Vec3.X, Vec3.init(isqrt2, isqrt2, 0)), epsilon);
    expectNear(Rotor3.init(isqrt2, 0, 0, isqrt2), try Rotor3.initVecs(Vec3.X.scale(5), Vec3.init(10, 10, 0)), epsilon);
    expectNear(Rotor3.init(isqrt2, 0, 0, isqrt2), Rotor3.initVecsNormalized(Vec3.X, Vec3.init(isqrt2, isqrt2, 0)), epsilon);
}

test "Rotor3.diffVec" {
    const epsilon = 1e-5;
    const Identity = Rotor3.Identity;
    const expectNear = Rotor3.expectNear;
    expectNear(Identity, try Rotor3.diffVec(Vec3.X, Vec3.X), epsilon);
    expectNear(Identity, try Rotor3.diffVec(Vec3.Y, Vec3.Y), epsilon);
    expectNear(Identity, try Rotor3.diffVec(Vec3.Z, Vec3.Z), epsilon);

    expectNear(Rotor3.init(0, 0, -1, 0), try Rotor3.diffVec(Vec3.X, Vec3.X.negate()), epsilon);
    expectNear(Rotor3.init(0, 0, 0, 1), try Rotor3.diffVecAlong(Vec3.X, Vec3.X.negate(), BiVec3.XY), epsilon);
    expectNear(Rotor3.init(0, 0, 0, -1), try Rotor3.diffVecAlong(Vec3.X, Vec3.X.negate(), BiVec3.XY.negate()), epsilon);
    expectNear(Rotor3.init(0, 0, -1, 0), try Rotor3.diffVecAlong(Vec3.X, Vec3.X.negate(), BiVec3.ZX.negate()), epsilon);

    testing.expectError(error.Singular, Rotor3.diffVecAlong(Vec3.X, Vec3.X.negate(), BiVec3.YZ.negate()));

    const isqrt2 = 1.0 / math.sqrt(2.0);
    expectNear(Rotor3.init(isqrt2, 0, 0, isqrt2), try Rotor3.diffVec(Vec3.X, Vec3.Y), epsilon);
    expectNear(Rotor3.init(isqrt2, 0, 0, isqrt2), try Rotor3.diffVec(Vec3.X.scale(5), Vec3.Y.scale(10)), epsilon);
    expectNear(Rotor3.init(isqrt2, 0, -isqrt2, 0), try Rotor3.diffVec(Vec3.X, Vec3.Z), epsilon);
}

test "Rotor3.halfway" {
    const epsilon = 1e-5;
    const rotor = try Rotor3.init(1, 2, -3, 4).normalize();
    var half = rotor.halfway();

    const vec = Vec3.init(4, -2, 12);
    const rotated = rotor.apply(vec);
    const hrotated = half.apply(half.apply(vec));
    Vec3.expectNear(rotated, hrotated, epsilon);

    var c: u32 = 0;
    while (c < 32) : (c += 1) {
        half = half.halfway();
    }
    Rotor3.expectNear(Rotor3.Identity, half, epsilon);
}

test "Rotor3.apply" {
    const epsilon = 1e-5;
    const Identity = Rotor3.Identity;
    const expectNear = Rotor3.expectNear;
    const isqrt2 = 1.0 / math.sqrt(2.0);

    var rotor = Rotor3.init(isqrt2, 0, 0, isqrt2);
    Vec3.expectNear(Vec3.Y, rotor.apply(Vec3.X), epsilon);
}

test "Rotor3.diffFrame" {
    const epsilon = 1e-5;
    const expectNear = Rotor3.expectNear;
    const rotor = try Rotor3.diffFrame(
        Vec3.init(4, 0, 0),
        Vec3.init(-0.5, 0, 1),
        Vec3.init(0, 0.25, 0),
        Vec3.init(1, 0.5, 0),
    );
    Vec3.expectNear(Vec3.Y, rotor.apply(Vec3.X), epsilon);
    Vec3.expectNear(Vec3.Y.add(Vec3.X), rotor.apply(Vec3.X.add(Vec3.Z)), epsilon);
}

fn randRotor3(rnd: *std.rand.Random) Rotor3 {
    return Rotor3.init(
        rnd.float(f32) * 2 - 1,
        rnd.float(f32) * 2 - 1,
        rnd.float(f32) * 2 - 1,
        rnd.float(f32) * 2 - 1,
    ).standardize().normalize() catch Rotor3.Identity;
}

fn randVec3(rnd: *std.rand.Random) Vec3 {
    return Vec3.init(
        rnd.float(f32) * 4 - 2,
        rnd.float(f32) * 4 - 2,
        rnd.float(f32) * 4 - 2,
    );
}

test "Rotor3.diff" {
    const epsilon = 1e-5;
    var bigRnd = std.rand.DefaultPrng.init(42);
    const rnd = &bigRnd.random;

    var i = u32(0);
    while (i < 10) : (i += 1) {
        const a = randRotor3(rnd);
        const b = randRotor3(rnd);
        const diff = a.diff(b);
        const recombined = diff.preMul(a);
        Rotor3.expectNear(b, recombined, epsilon);
        var j = u32(0);
        while (j < 10) : (j += 1) {
            const vec = randVec3(rnd);
            Vec3.expectNear(b.apply(vec), diff.apply(a.apply(vec)), epsilon);
        }
    }
}

test "Rotor3.lerp" {
    const epsilon = 1e-5;
    var bigRnd = std.rand.DefaultPrng.init(42);
    const rnd = &bigRnd.random;
    var i = u32(0);
    while (i < 10) : (i += 1) {
        const a = randRotor3(rnd);
        const b = randRotor3(rnd);
        const halfDiff = a.diff(b).halfway().preMul(a);
        const slerp = a.slerp(b, 0.5);
        const nlerp = try a.nlerp(b, 0.5);
        Rotor3.expectNear(slerp, nlerp, epsilon);
        Rotor3.expectNear(slerp, halfDiff, epsilon);
    }
}
