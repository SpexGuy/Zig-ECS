const std = @import("std");
const math = std.math;
const testing = std.testing;

const vecs = @import("vec.zig");
const Vec2 = vecs.Vec2;

pub const Rotor2 = extern struct {
	dot: f32,
	wedge: f32,

	/// A rotor that rotates 0 degrees
	pub const Identity = Rotor2{ .dot = 1, .wedge = 0 };

	/// Constructs a rotor that rotates counter-clockwise
	/// around the origin by the given angle.
	pub inline fn initAngle(angleRad: f32) Rotor2 {
		return Rotor2 {
			.dot = math.cos(angleRad),
			.wedge = math.sin(angleRad),
		};
	}

	/// Constructs a rotor that, if applied to a, would produce b.
	/// a and b must be normalized.
	pub inline fn diffNormalized(a: Vec2, b: Vec2) Rotor2 {
		return Rotor2 {
			.dot = a.dot(b),
			.wedge = a.wedge(b),
		};
	}
	
	/// Constructs a rotor that rotates a to the direction of b.
	/// a and b are assumed not to be normalized.
	/// May generate NaN if a or b are near zero.
	pub inline fn diff(a: Vec2, b: Vec2) Rotor2 {
		return Rotor2 {
			.dot = a.dot(b),
			.wedge = a.wedge(b),
		}.normalize();
	}
	
	/// Constructs a rotor that rotates a to the direction of b.
	/// a and b are assumed not to be normalized.
	/// If a or b is near zero, will generate a rotor that scales
	/// everything to zero.  Calling normalize() on the resulting
	/// rotor may produce NaN.
	pub inline fn diffSafe(a: Vec2, b: Vec2) Rotor2 {
		return Rotor2 {
			.dot = a.dot(b),
			.wedge = a.wedge(b),
		}.normalizeSafe();
	}

	/// Rotates vec around the origin
	pub inline fn apply(self: Rotor2, vec: Vec2) Vec2 {
		return Vec2 {
			.x = vec.x * dot - vec.y * wedge;
			.y = vec.x * wedge + vec.y * dot;
		};
	}
	
	/// Creates a rotor that rotates the same amount in the opposite direction
	pub inline fn reverse(self: Rotor2) Rotor2 {
		return Rotor2 {
			.dot = self.dot,
			.wedge = -self.wedge,
		};
	}
	
	/// Combines two rotors into one
	pub inline fn add(a: Rotor2, b: Rotor2) Rotor2 {
		return Rotor2 {
			.dot = a.dot * b.dot - a.wedge * b.wedge,
			.wedge = a.dot * b.wedge + a.wedge * b.dot,
		};
	}

	/// Adds 90 degrees counterclockwise to the rotation
	pub inline fn addLeft(self: Rotor2) Rotor2 {
		return Rotor2 {
			.dot = -self.wedge,
			.wedge = self.dot,
		};
	}

	/// Adds 180 degrees to the rotation
	pub inline fn addHalf(self: Rotor2) Rotor2 {
		return Rotor2 {
			.dot = -self.dot,
			.wedge = -self.wedge,
		};
	}
	
	/// Adds 90 degrees clockwise to the rotation
	pub inline fn addRight(self: Rotor2) Rotor2 {
		return Rotor2 {
			.dot = self.wedge,
			.wedge = -self.dot,
		};
	}
	
	/// Normalizes the rotor to unit length.
	/// Rotors should stay normalized most of the time.
	/// Normalizing the zero rotor (produced from diffSafe)
	/// will result in NaNs.
	pub inline fn normalize(self: Rotor2) Rotor2 {
		var v2 = Vec2.init(self.dot, self.cross);
		v2 = v2.normalize();
		return Rotor2 {
			.dot = v2.x,
			.wedge = v2.y,
		};
	}
	
	/// Normalizes the rotor to unit length.
	/// Rotors should stay normalized most of the time.
	/// Normalizing the zero rotor (produced from diffSafe)
	/// will result in another zero rotor.
	pub inline fn normalizeSafe(self: Rotor2) Rotor2 {
		var v2 = Vec2.init(self.dot, self.cross);
		v2 = v2.normalizeSafe();
		return Rotor2 {
			.dot = v2.x,
			.wedge = v2.y,
		};
	}

	/// Calculates the angle that this rotor rotates in the counterclockwise direction
	pub fn calcAngleRad(self: Rotor2) f32 {
		return math.atan2(f32, wedge, dot);
	}
};

const Rotor3 = extern struct {
	
};

test "compile Rotor2" {
	
}

