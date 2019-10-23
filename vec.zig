const std = @import("std");
const math = std.math;
const testing = std.testing;

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
    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{
            .x = x,
            .y = y,
            .z = z,
        };
    }

    /// Creates a vector with each component set to the given value
    pub fn splat(val: f32) Vec3 {
        return Vec3{
            .x = val,
            .y = val,
            .z = val,
        };
    }

    /// Adds the like components of the inputs
    pub fn add(self: Vec3, other: Vec3) Vec3 {
        return Vec3{
            .x = self.x + other.x,
            .y = self.y + other.y,
            .z = self.z + other.z,
        };
    }

    /// Negates each component
    pub fn negate(self: Vec3) Vec3 {
        return Vec3{
            .x = -self.x,
            .y = -self.y,
            .z = -self.z,
        };
    }

    /// Multiply each component by a constant
    pub fn scale(self: Vec3, multiple: f32) Vec3 {
        return Vec3{
            .x = self.x * multiple,
            .y = self.y * multiple,
            .z = self.z * multiple,
        };
    }

    /// Component-wise multiply two vectors
    pub fn mul(self: Vec3, mult: Vec3) Vec3 {
        return Vec3{
            .x = self.x * mult.x,
            .y = self.y * mult.y,
            .z = self.z * mult.z,
        };
    }

    /// Scale the vector to length 1.
    /// Can produce NaN if the vector length is close enough to zero.
    pub fn normalize(self: Vec3) Vec3 {
        const mult = 1.0 / self.len();
        return self.scale(mult);
    }

    /// Adds the x, y, and z components of the vector
    pub fn sum(self: Vec3) f32 {
        return self.x + self.y + self.z;
    }

    /// Returns the square of the length of the vector.
    /// Slightly faster than calculating the length.
    pub fn lenSquared(self: Vec3) f32 {
        return self.x * self.x + self.y * self.y + self.z * self.z;
    }

    /// Computes the length of the vector
    pub fn len(self: Vec3) f32 {
        return math.sqrt(self.lenSquared());
    }

    /// Computes the dot product of two vectors
    pub fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }

    /// Computes the cross product of two vectors
    pub fn cross(self: Vec3, other: Vec3) Vec3 {
        return Vec3{
            .x = self.y * other.z - self.z * other.y,
            .y = self.z * other.x - self.x * other.z,
            .z = self.x * other.y - self.y * other.x,
        };
    }

    /// Returns a pointer to the vector's data as a fixed-size buffer.
    pub fn asBuf(self: *Vec3) *[3]f32 {
        return @ptrCast(*[3]f32, self);
    }

    pub fn asConstBuf(self: *const Vec3) *const [3]f32 {
        return @ptrCast(*const [3]f32, self);
    }

    /// Returns a slice of the vector's data.
    pub fn asSlice(self: *Vec3) []f32 {
        return self.asBuf()[0..];
    }

    pub fn asConstSlice(self: *const Vec3) []const f32 {
        return self.asConstBuf()[0..];
    }
};

test "compile Vec3" {
    var a = Vec3.init(0.5, 0, 1);
    var b = Vec3.splat(2);
    const c = a.add(b);
    _ = b.negate();
    _ = c.scale(5);
    _ = a.mul(b);
    _ = c.normalize();
    _ = a.sum();
    _ = b.lenSquared();
    _ = c.len();
    _ = c.dot(c);
    _ = c.cross(a);
    _ = b.asBuf();
    _ = b.asConstBuf();
    const slice = b.asSlice();
    _ = b.asConstSlice();
    _ = c.asConstBuf();
    _ = c.asConstSlice();
    testing.expectEqual(usize(3), slice.len);
    testing.expectEqual(f32(2), slice[1]);
    slice[1] = 0;
    testing.expectEqual(f32(0), b.y);
}
