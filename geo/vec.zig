const std = @import("std");
const math = std.math;
const testing = std.testing;

/// A 2-dimensional vector, representing the quantity x*e1 + y*e2.
pub const Vec2 = extern struct {
    pub x: f32,
    pub y: f32,

    /// (0,0)
    pub const Zero = init(0, 0);

    /// (1,0)
    pub const X = init(1, 0);

    /// (0,1)
    pub const Y = init(0, 1);

    /// Creates a vector with the given values
    pub inline fn init(x: f32, y: f32) Vec2 {
        return Vec2{
            .x = x,
            .y = y,
        };
    }

    /// Creates a vector with each component set to the given value
    pub inline fn splat(val: f32) Vec2 {
        return Vec2{
            .x = val,
            .y = val,
        };
    }

    /// Adds the like components of the inputs
    pub inline fn add(self: Vec2, other: Vec2) Vec2 {
        return Vec2{
            .x = self.x + other.x,
            .y = self.y + other.y,
        };
    }

    /// Subtracts the like components of the inputs
    pub inline fn sub(self: Vec2, other: Vec2) Vec2 {
        return Vec2{
            .x = self.x - other.x,
            .y = self.y - other.y,
        };
    }

    /// Returns the vector from self to other.
    /// Equivalent to other.sub(self);.
    pub inline fn diff(self: Vec2, other: Vec2) Vec2 {
        return other.sub(self);
    }

    /// Negates each component
    pub inline fn negate(self: Vec2) Vec2 {
        return Vec2{
            .x = -self.x,
            .y = -self.y,
        };
    }

    /// Multiply each component by a constant
    pub inline fn scale(self: Vec2, multiple: f32) Vec2 {
        return Vec2{
            .x = self.x * multiple,
            .y = self.y * multiple,
        };
    }

    /// Component-wise multiply two vectors
    pub inline fn mul(self: Vec2, mult: Vec2) Vec2 {
        return Vec2{
            .x = self.x * mult.x,
            .y = self.y * mult.y,
        };
    }

    /// Scale the vector to length 1.
    /// If the vector is too close to zero, this returns error.Singular.
    pub inline fn normalize(self: Vec2) !Vec2 {
        const mult = 1.0 / self.len();
        if (!math.isFinite(mult)) return error.Singular;
        return self.scale(mult);
    }

    /// Adds the x and y components of the vector
    pub inline fn sum(self: Vec2) f32 {
        return self.x + self.y;
    }

    /// Interpolates alpha percent between self and target.
    /// If alpha is < 0 or > 1, will extrapolate.
    pub inline fn lerp(self: Vec2, target: Vec2, alpha: f32) Vec2 {
        return Vec2{
            .x = self.x + (target.x - self.x) * alpha,
            .y = self.y + (target.y - self.y) * alpha,
        };
    }

    /// Returns the square of the length of the vector.
    /// Slightly faster than calculating the length.
    pub inline fn lenSquared(self: Vec2) f32 {
        return self.x * self.x + self.y * self.y;
    }

    /// Computes the length of the vector
    pub inline fn len(self: Vec2) f32 {
        return math.sqrt(self.lenSquared());
    }

    /// Computes the dot product of two vectors
    pub inline fn dot(self: Vec2, other: Vec2) f32 {
        return self.x * other.x + self.y * other.y;
    }

    /// Computes the wedge product of two vectors.
    /// (A.K.A. the 2D cross product)
    pub inline fn wedge(self: Vec2, other: Vec2) f32 {
        return self.x * other.y - self.y * other.x;
    }

    /// Computes the projection of self along other.
    /// If other is near zero, returns error.Singular.
    pub inline fn along(self: Vec2, other: Vec2) !Vec2 {
        const mult = self.dot(other) / other.lenSquared();
        if (!math.isFinite(mult)) return error.Singular;
        return other.scale(mult);
    }

    /// Computes the projection of self across other.
    /// Equivalent to the projection of self along other.left().
    /// This is sometimes referred to as the rejection.
    /// If other is near zero, returns error.Singular.
    pub inline fn across(self: Vec2, other: Vec2) !Vec2 {
        const mult = self.wedge(other) / other.lenSquared();
        if (!math.isFinite(mult)) return error.Singular;
        return other.scale(mult);
    }

    /// Reflects self across axis.  If axis is near zero,
    /// will return error.Singular.
    pub fn reflect(self: Vec2, axis: Vec2) !Vec2 {
        const invAxisLenSquared = 1.0 / axis.lenSquared();
        if (!math.isFinite(invAxisLenSquared)) return error.Singular;
        const alongMult = self.dot(axis);
        const acrossMult = self.wedge(axis);
        const vector = axis.scale(alongMult).sub(axis.left().scale(acrossMult));
        return vector.scale(invAxisLenSquared);
    }

    /// Finds x and y such that x * xVec + y * yVec == self.
    /// If xVec ^ yVec is close to zero, returns error.Singular.
    pub fn changeBasis(self: Vec2, xVec: Vec2, yVec: Vec2) !Vec2 {
        const mult = 1.0 / xVec.wedge(yVec);
        if (!math.isFinite(mult)) return error.Singular;
        const x = self.wedge(yVec) * mult;
        const y = xVec.wedge(self) * mult;
        return init(x, y);
    }

    /// Computes the vector rotated 90 degrees counterclockwise.
    /// This is the vector pointing out of the left side of this vector,
    /// with the same length as this vector.
    pub inline fn left(self: Vec2) Vec2 {
        return Vec2{
            .x = -self.y,
            .y = self.x,
        };
    }

    /// Computes the vector rotated 90 degrees clockwise.
    /// This is the vector pointing out of the right side of this vector,
    /// with the same length as this vector.
    pub inline fn right(self: Vec2) Vec2 {
        return Vec2{
            .x = self.y,
            .y = -self.x,
        };
    }

    /// Returns a pointer to the vector's data as a fixed-size buffer.
    pub inline fn asBuf(self: *Vec2) *[2]f32 {
        return @ptrCast(*[2]f32, self);
    }

    /// Returns a pointer to the vector's data as a const fixed-size buffer.
    pub inline fn asConstBuf(self: *const Vec2) *const [2]f32 {
        return @ptrCast(*const [2]f32, self);
    }

    /// Returns a slice of the vector's data.
    pub inline fn asSlice(self: *Vec2) []f32 {
        return self.asBuf()[0..];
    }

    /// Returns a const slice of the vector's data.
    pub inline fn asConstSlice(self: *const Vec2) []const f32 {
        return self.asConstBuf()[0..];
    }

    /// Appends a z value to make a Vec3
    pub inline fn toVec3(self: Vec2, z: f32) Vec3 {
        return Vec3.init(self.x, self.y, z);
    }

    /// Appends z and w values to make a Vec4
    pub inline fn toVec4(self: Vec2, z: f32, w: f32) Vec4 {
        return Vec4.init(self.x, self.y, z, w);
    }

    /// Concatenates two Vec2s into a Vec4
    pub inline fn pack4(xy: Vec2, zw: Vec2) Vec4 {
        return Vec4.init(xy.x, xy.y, zw.x, zw.y);
    }
};

/// A 3-dimensional vector, representing the quantity x*e1 + y*e2 + z*e3.
pub const Vec3 = extern struct {
    pub x: f32,
    pub y: f32,
    pub z: f32,

    /// (0,0,0)
    pub const Zero = init(0, 0, 0);

    /// (1,0,0)
    pub const X = init(1, 0, 0);

    /// (0,1,0)
    pub const Y = init(0, 1, 0);

    /// (0,0,1)
    pub const Z = init(0, 0, 1);

    /// Creates a vector with the given values
    pub inline fn init(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{
            .x = x,
            .y = y,
            .z = z,
        };
    }

    /// Creates a vector with each component set to the given value
    pub inline fn splat(val: f32) Vec3 {
        return Vec3{
            .x = val,
            .y = val,
            .z = val,
        };
    }

    /// Adds the like components of the inputs
    pub inline fn add(self: Vec3, other: Vec3) Vec3 {
        return Vec3{
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
        };
    }

    /// Subtracts the like components of the inputs
    pub inline fn sub(self: Vec3, other: Vec3) Vec3 {
        return Vec3{
            .x = self.x - other.x,
            .y = self.y - other.y,
            .z = self.z - other.z,
        };
    }

    /// Returns the vector from self to other.
    /// Equivalent to other.sub(self);.
    pub inline fn diff(self: Vec3, other: Vec3) Vec3 {
        return other.sub(self);
    }

    /// Negates each component
    pub inline fn negate(self: Vec3) Vec3 {
        return Vec3{
            .x = -self.x,
            .y = -self.y,
            .z = -self.z,
        };
    }

    /// Multiply each component by a constant
    pub inline fn scale(self: Vec3, multiple: f32) Vec3 {
        return Vec3{
            .x = self.x * multiple,
            .y = self.y * multiple,
            .z = self.z * multiple,
        };
    }

    /// Component-wise multiply two vectors
    pub inline fn mul(self: Vec3, mult: Vec3) Vec3 {
        return Vec3{
            .x = self.x * mult.x,
            .y = self.y * mult.y,
            .z = self.z * mult.z,
        };
    }

    /// Scale the vector to length 1.
    /// If the vector is too close to zero, this returns error.Singular.
    pub inline fn normalize(self: Vec3) !Vec3 {
        const mult = 1.0 / self.len();
        if (!math.isFinite(mult)) return error.Singular;
        return self.scale(mult);
    }

    /// Adds the x, y, and z components of the vector
    pub inline fn sum(self: Vec3) f32 {
        return self.x + self.y + self.z;
    }

    /// Interpolates alpha percent between self and target.
    /// If alpha is < 0 or > 1, will extrapolate.
    pub inline fn lerp(self: Vec3, target: Vec3, alpha: f32) Vec3 {
        return Vec3{
            .x = self.x + (target.x - self.x) * alpha,
            .y = self.y + (target.y - self.y) * alpha,
            .z = self.z + (target.z - self.z) * alpha,
        };
    }

    /// Returns the square of the length of the vector.
    /// Slightly faster than calculating the length.
    pub inline fn lenSquared(self: Vec3) f32 {
        return self.x * self.x + self.y * self.y + self.z * self.z;
    }

    /// Computes the length of the vector
    pub inline fn len(self: Vec3) f32 {
        return math.sqrt(self.lenSquared());
    }

    /// Computes the dot product of two vectors
    pub inline fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    /// Computes the wedge product of two vectors
    pub inline fn wedge(self: Vec3, other: Vec3) BiVec3 {
        return BiVec3{
            .xy = self.x * other.y - self.y * other.x,
            .yz = self.y * other.z - self.z * other.y,
            .zx = self.z * other.x - self.x * other.z,
        };
    }

    /// Computes the cross product of two vectors
    pub inline fn cross(self: Vec3, other: Vec3) Vec3 {
        return Vec3{
            .x = self.y * other.z - self.z * other.y,
            .y = self.z * other.x - self.x * other.z,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    /// Computes the projection of self along other.
    /// If other is near zero, returns error.Singular.
    pub inline fn along(self: Vec3, other: Vec3) !Vec3 {
        const mult = self.dot(other) / other.lenSquared();
        if (!math.isFinite(mult)) return error.Singular;
        return if (math.isFinite(mult)) other.scale(mult) else Zero;
    }

    /// Computes the projection of self across other.
    /// This is sometimes referred to as the rejection.
    /// If other is near zero, returns error.Singular.
    pub inline fn across(self: Vec3, other: Vec3) !Vec3 {
        // TODO How does this work in 3D?
        return error.Singular;
    }

    /// Returns a pointer to the vector's data as a fixed-size buffer.
    pub inline fn asBuf(self: *Vec3) *[3]f32 {
        return @ptrCast(*[3]f32, self);
    }

    /// Returns a pointer to the vector's data as a const fixed-size buffer.
    pub inline fn asConstBuf(self: *const Vec3) *const [3]f32 {
        return @ptrCast(*const [3]f32, self);
    }

    /// Returns a slice of the vector's data.
    pub inline fn asSlice(self: *Vec3) []f32 {
        return self.asBuf()[0..];
    }

    /// Returns a const slice of the vector's data.
    pub inline fn asConstSlice(self: *const Vec3) []const f32 {
        return self.asConstBuf()[0..];
    }

    /// Returns a Vec2 representation of this vector
    /// Modifications to the returned Vec2 will also
    /// modify this vector, and vice versa.
    pub inline fn asVec2(self: *Vec3) *Vec2 {
        return @ptrCast(*Vec2, self);
    }

    /// Returns a vec2 of the x and y components of this vector
    pub inline fn toVec2(self: Vec3) Vec2 {
        return Vec2.init(self.x, self.y);
    }

    /// Appends a w value to make a vec4
    pub inline fn toVec4(self: Vec3, w: f32) Vec4 {
        return Vec4.init(self.x, self.y, self.z, w);
    }

    /// Provides a view over this vector as a BiVec3
    pub inline fn asBiVec3(self: *Vec3) *BiVec3 {
        return @ptrCast(*BiVec3, self);
    }

    /// Returns the BiVec3 representation of this vector.
    /// This is the bivector normal to this vector with area
    /// equal to the length of this vector.  This is equal
    /// to this vector times the unit trivector.
    pub inline fn toBiVec3(self: Vec3) BiVec3 {
        return @bitCast(BiVec3, self);
    }
};

/// A 4-dimensional vector, representing the quantity x*e1 + y*e2 + z*e3 + w*e4.
pub const Vec4 = extern struct {
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub w: f32,

    /// (0,0,0,0)
    pub const Zero = init(0, 0, 0, 0);

    /// (1,0,0,0)
    pub const X = init(1, 0, 0, 0);

    /// (0,1,0,0)
    pub const Y = init(0, 1, 0, 0);

    /// (0,0,1,0)
    pub const Z = init(0, 0, 1, 0);

    /// (0,0,0,1)
    pub const W = init(0, 0, 0, 1);

    /// Creates a vector with the given values
    pub inline fn init(x: f32, y: f32, z: f32, w: f32) Vec4 {
        return Vec4{
            .x = x,
            .y = y,
            .z = z,
            .w = w,
        };
    }

    /// Creates a vector with each component set to the given value
    pub inline fn splat(val: f32) Vec4 {
        return Vec4{
            .x = val,
            .y = val,
            .z = val,
            .w = val,
        };
    }

    /// Adds the like components of the inputs
    pub inline fn add(self: Vec4, other: Vec4) Vec4 {
        return Vec4{
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
            .w = self.w + other.w,
        };
    }

    /// Subtracts the like components of the inputs
    pub inline fn sub(self: Vec4, other: Vec4) Vec4 {
        return Vec4{
            .x = self.x - other.x,
            .y = self.y - other.y,
            .z = self.z - other.z,
            .w = self.w - other.w,
        };
    }

    /// Returns the vector from self to other.
    /// Equivalent to other.sub(self);.
    pub inline fn diff(self: Vec4, other: Vec4) Vec4 {
        return other.sub(self);
    }

    /// Negates each component
    pub inline fn negate(self: Vec4) Vec4 {
        return Vec4{
            .x = -self.x,
            .y = -self.y,
            .z = -self.z,
            .w = -self.w,
        };
    }

    /// Multiply each component by a constant
    pub inline fn scale(self: Vec4, multiple: f32) Vec4 {
        return Vec4{
            .x = self.x * multiple,
            .y = self.y * multiple,
            .z = self.z * multiple,
            .w = self.w * multiple,
        };
    }

    /// Component-wise multiply two vectors
    pub inline fn mul(self: Vec4, mult: Vec4) Vec4 {
        return Vec4{
            .x = self.x * mult.x,
            .y = self.y * mult.y,
            .z = self.z * mult.z,
            .w = self.w * mult.w,
        };
    }

    /// Scale the vector to length 1.
    /// If the vector is too close to zero, this returns error.Singular.
    pub inline fn normalize(self: Vec4) !Vec4 {
        const mult = 1.0 / self.len();
        if (!math.isFinite(mult)) return error.Singular;
        return self.scale(mult);
    }

    /// Divides by the w value to do perspective division.
    /// If the w value is too close to zero, returns error.Singular.
    pub inline fn perspective(self: Vec4) !Vec3 {
        const mult = 1.0 / self.w;
        if (!math.isFinite(mult)) return error.Singular;
        return self.toVec3().scale(mult);
    }

    /// Divides by the w value to do perspective division.
    /// If the w value is too close to zero, returns error.Singular.
    pub inline fn perspective4(self: Vec4) !Vec4 {
        const mult = 1.0 / self.w;
        if (!math.isFinite(mult)) return error.Singular;
        return self.scale(mult);
    }

    /// Adds the x, y, and z components of the vector
    pub inline fn sum(self: Vec4) f32 {
        return self.x + self.y + self.z;
    }

    /// Interpolates alpha percent between self and target.
    /// If alpha is < 0 or > 1, will extrapolate.
    pub inline fn lerp(self: Vec4, target: Vec4, alpha: f32) Vec4 {
        return Vec4{
            .x = self.x + (target.x - self.x) * alpha,
            .y = self.y + (target.y - self.y) * alpha,
            .z = self.z + (target.z - self.z) * alpha,
            .w = self.w + (target.w - self.w) * alpha,
        };
    }

    /// Returns the square of the length of the vector.
    /// Slightly faster than calculating the length.
    pub inline fn lenSquared(self: Vec4) f32 {
        return self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w;
    }

    /// Computes the length of the vector
    pub inline fn len(self: Vec4) f32 {
        return math.sqrt(self.lenSquared());
    }

    /// Computes the dot product of two vectors
    pub inline fn dot(self: Vec4, other: Vec4) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z + self.w * other.w;
    }

    /// Computes the projection of self along other.
    /// If other is too close to zero, returns error.Singular.
    pub inline fn along(self: Vec4, other: Vec4) !Vec4 {
        const mult = self.dot(other) / other.lenSquared();
        if (!math.isFinite(mult)) return error.Singular;
        return other.scale(mult);
    }

    /// Returns a pointer to the vector's data as a fixed-size buffer.
    pub inline fn asBuf(self: *Vec4) *[4]f32 {
        return @ptrCast(*[4]f32, self);
    }

    /// Returns a pointer to the vector's data as a const fixed-size buffer.
    pub inline fn asConstBuf(self: *const Vec4) *const [4]f32 {
        return @ptrCast(*const [4]f32, self);
    }

    /// Returns a slice of the vector's data.
    pub inline fn asSlice(self: *Vec4) []f32 {
        return self.asBuf()[0..];
    }

    /// Returns a const slice of the vector's data.
    pub inline fn asConstSlice(self: *const Vec4) []const f32 {
        return self.asConstBuf()[0..];
    }

    /// Returns a Vec2 representation of this vector
    /// Modifications to the returned Vec2 will also
    /// modify this vector, and vice versa.
    pub inline fn asVec2(self: *Vec4) *Vec2 {
        return @ptrCast(*Vec2, self);
    }

    /// Returns a Vec3 representation of this vector
    /// Modifications to the returned Vec2 will also
    /// modify this vector, and vice versa.
    pub inline fn asVec3(self: *Vec4) *Vec3 {
        return @ptrCast(*Vec3, self);
    }

    /// Returns a vec2 of the x and y components of this vector
    pub inline fn toVec2(self: Vec4) Vec2 {
        return Vec2.init(self.x, self.y);
    }

    /// Returns a vec3 of the xyz components of this vector
    pub inline fn toVec3(self: Vec4) Vec3 {
        return Vec3.init(self.x, self.y, self.z);
    }
};

/// A 3-dimensional bivector, representing the quantity xy*e1^e2 + yz*e2^e3 + zx*e3^e1.
pub const BiVec3 = extern struct {
    // Field order is set up here to match that of Vec3,
    // so BitCasting a Vec3 to a BiVec3 is equivalent to
    // Vec3.dual(..)
    pub yz: f32,
    pub zx: f32,
    pub xy: f32,

    /// (0,0,0)
    pub const Zero = init(0, 0, 0);

    /// (1,0,0)
    pub const YZ = init(1, 0, 0);

    /// (0,1,0)
    pub const ZX = init(0, 1, 0);

    /// (0,0,1)
    pub const XY = init(0, 0, 1);

    /// Creates a BiVec3 with the given components
    pub inline fn init(yz: f32, zx: f32, xy: f32) BiVec3 {
        return BiVec3{
            .yz = yz,
            .zx = zx,
            .xy = xy,
        };
    }

    /// Add two bivectors
    pub inline fn add(self: BiVec3, other: BiVec3) BiVec3 {
        return BiVec3{
            .yz = self.yz + other.yz,
            .zx = self.zx + other.zx,
            .xy = self.xy + other.xy,
        };
    }

    /// Reverse the orientation of the bivector without
    /// changing its magnitude.
    pub inline fn negate(self: BiVec3) BiVec3 {
        return BiVec3{
            .yz = -self.yz,
            .zx = -self.zx,
            .xy = -self.xy,
        };
    }

    /// Dots with another bivector and returns a scalar.
    /// Note that this is NOT the same as a vector dot product.
    pub inline fn dot(self: BiVec3, other: BiVec3) f32 {
        return -(self.yz * other.yz) - (self.zx * other.zx) - (self.xy * other.xy);
    }

    /// Wedges with another bivector and returns a bivector.
    /// Note that this is NOT the same as a vector wedge/cross product.
    pub inline fn wedge(self: BiVec3, other: BiVec3) BiVec3 {
        return BiVec3{
            .yz = self.xy * other.zx - self.zx * other.xy,
            .zx = self.yz * other.xy - self.xy * other.yz,
            .xy = self.zx * other.yz - self.yz * other.zx,
        };
    }

    /// Wedges with a vector and returns a trivector.
    /// This value is equivalent to the scalar triple product.
    /// Note that this is NOT the same as a vector wedge/cross product.
    pub inline fn wedgeVec(self: BiVec3, other: Vec3) f32 {
        return self.yz * other.x + self.zx * other.y + self.xy * other.z;
    }

    /// Dots with a vector and returns a vector.
    /// This value is equivalent to the vector triple product.
    /// Note that this is NOT the same as a vector dot product.
    pub inline fn dotVec(self: BiVec3, other: Vec3) Vec3 {
        return @bitCast(Vec3, self).cross(other);
    }

    /// Multiply each component by a constant
    pub inline fn scale(self: BiVec3, multiple: f32) BiVec3 {
        return BiVec3{
            .yz = self.yz * multiple,
            .zx = self.zx * multiple,
            .xy = self.xy * multiple,
        };
    }

    /// Returns a pointer to the vector's data as a fixed-size buffer.
    pub inline fn asBuf(self: *Vec4) *[3]f32 {
        return @ptrCast(*[3]f32, self);
    }

    /// Returns a pointer to the vector's data as a const fixed-size buffer.
    pub inline fn asConstBuf(self: *const Vec4) *const [3]f32 {
        return @ptrCast(*const [3]f32, self);
    }

    /// Returns a slice of the vector's data.
    pub inline fn asSlice(self: *Vec4) []f32 {
        return self.asBuf()[0..];
    }

    /// Returns a const slice of the vector's data.
    pub inline fn asConstSlice(self: *const Vec4) []const f32 {
        return self.asConstBuf()[0..];
    }

    /// Provide a Vec3 view over this BiVector.
    /// x maps to yz, y maps to zx, z maps to xy.
    pub inline fn asVec3(self: *BiVec3) *Vec3 {
        return @ptrCast(*Vec3, self);
    }

    /// Copies into a Vec3.
    /// x maps to yz, y maps to zx, z maps to xy.
    pub inline fn toVec3(self: BiVec3) Vec3 {
        return @bitCast(Vec3, self);
    }
};

test "compile Vec2" {
    var a = Vec2.init(0.5, 0);
    var b = Vec2.splat(2);
    const c = a.add(b);
    _ = a.sub(b);
    _ = a.diff(b);
    _ = b.negate();
    _ = c.scale(5);
    _ = a.mul(b);
    _ = try c.normalize();
    _ = a.sum();
    _ = a.lerp(b, 0.25);
    _ = b.lenSquared();
    _ = c.len();
    _ = c.dot(c);
    _ = c.wedge(a);
    _ = try a.along(b);
    _ = try a.across(b);
    _ = a.reflect(b) catch a;
    _ = try a.changeBasis(b, c);
    _ = b.left();
    _ = a.right();
    _ = b.asBuf();
    _ = b.asConstBuf();
    const slice = b.asSlice();
    _ = b.asConstSlice();
    _ = c.asConstBuf();
    _ = c.asConstSlice();
    _ = b.toVec3(1);
    _ = b.toVec4(0, 1);
    _ = Vec2.pack4(b, a);
    testing.expectEqual(usize(2), slice.len);
    testing.expectEqual(f32(2), slice[1]);
    slice[1] = 4;
    testing.expectEqual(f32(4), b.y);
}

test "compile Vec3" {
    var a = Vec3.init(0.5, 0, 1);
    var b = Vec3.splat(2);
    const c = a.add(b);
    _ = a.sub(b);
    _ = a.diff(b);
    _ = b.negate();
    _ = c.scale(5);
    _ = a.mul(b);
    _ = try c.normalize();
    _ = a.sum();
    _ = a.lerp(b, 0.75);
    _ = b.lenSquared();
    _ = c.len();
    _ = c.dot(c);
    _ = c.wedge(a);
    _ = c.cross(a);
    _ = try c.along(a);
    _ = c.across(a) catch Vec3.Zero;
    _ = b.asBuf();
    _ = b.asConstBuf();
    const slice = b.asSlice();
    _ = b.asConstSlice();
    _ = c.asConstBuf();
    _ = c.asConstSlice();
    const as2 = b.asVec2();
    const val2 = b.toVec2();
    _ = b.toVec4(1);
    testing.expectEqual(usize(3), slice.len);
    testing.expectEqual(f32(2), slice[1]);
    slice[1] = 4;
    testing.expectEqual(f32(4), b.y);
    testing.expectEqual(f32(4), as2.y);
    as2.x = 7;
    testing.expectEqual(f32(7), b.x);
    testing.expectEqual(val2.x, 2);
}

test "compile Vec4" {
    var a = Vec4.init(0.5, 0, 1, 1);
    var b = Vec4.splat(2);
    const c = a.add(b);
    _ = a.sub(b);
    _ = a.diff(b);
    _ = b.negate();
    _ = c.scale(5);
    _ = a.mul(b);
    _ = try c.normalize();
    _ = try c.perspective();
    _ = try c.perspective4();
    _ = a.sum();
    _ = a.lerp(b, 0.5);
    _ = b.lenSquared();
    _ = c.len();
    _ = c.dot(c);
    _ = try c.along(b);
    _ = b.asBuf();
    _ = b.asConstBuf();
    const slice = b.asSlice();
    _ = b.asConstSlice();
    _ = c.asConstBuf();
    _ = c.asConstSlice();
    const as2 = b.asVec2();
    const val2 = b.toVec2();
    const as3 = b.asVec3();
    _ = b.toVec3();
    testing.expectEqual(usize(4), slice.len);
    testing.expectEqual(f32(2), slice[1]);
    slice[1] = 4;
    testing.expectEqual(f32(4), b.y);
    testing.expectEqual(f32(4), as2.y);
    testing.expectEqual(f32(4), as3.y);
    as2.x = 7;
    testing.expectEqual(f32(7), b.x);
    testing.expectEqual(f32(7), as3.x);
    testing.expectEqual(val2.x, 2);
}

test "compile BiVec3" {
    var a = BiVec3.init(0.5, 1, 0);
    var b = BiVec3.Zero;
    _ = a.dot(b);
    const c = a.wedge(b);
    _ = c.wedgeVec(Vec3.X);
    _ = c.dotVec(Vec3.X);
    _ = c.scale(4);
    _ = a.add(c);
}
