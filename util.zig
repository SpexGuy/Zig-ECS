const std = @import("std");
const assert = std.debug.assert;

/// Offsets the given pointer by the offset amount in bytes,
/// and casts the result to [*]T
pub fn adjustPtr(comptime T: type, ptr: var, offset: i32) [*]T {
    const base = @ptrCast([*]u8, ptr);
    return @ptrCast([*]T, base + offset);
}

/// Rounds up the given position to the next multiple of alignment.
/// alignment must be a power of two.
pub fn alignUp(pos: u32, alignment: u32) u32 {
    const alignMask = alignment - 1;
    assert(alignment & alignMask == 0);
    return (pos + alignMask) & ~alignMask;
}
