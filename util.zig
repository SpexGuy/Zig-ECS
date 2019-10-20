const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

pub const EmptyStruct = struct {};

pub fn typedSlice(comptime T: type, ptr: var, offset: usize, elemCount: usize) []T {
    const sliceStart = adjustPtr(T, ptr, @bitCast(isize, offset));
    return sliceStart[0..elemCount];
}

pub fn extractTypesFromUnion(comptime Type: type) [@memberCount(Type)]type {
    // ensure that the type is valid
    const info = @typeInfo(Type);
    switch (info) {
        .Union => {},
        else => @compileError("Parameter type must be a Union"),
    }

    // do the work
    const num = @memberCount(Type);
    comptime var types: [num]type = undefined;
    inline for (types) |_, i| {
        types[i] = @memberType(Type, i);
    }
    return types;
}

pub fn roundUpToPowerOfTwo(x: u32) u32 {
    return u32(1) << @truncate(u5, 32 - @clz(u32, x -% 1));
}

pub fn emptySlice(comptime T: type) []T {
    return ([*]T)(undefined)[0..0];
}

pub fn isAlignedPtr(value: var, alignment: u29) bool {
    return isAligned(@ptrToInt(value), alignment);
}

pub fn isAligned(value: usize, alignment: u29) bool {
    assert(isPowerOfTwo(alignment));
    return (value & (alignment - 1)) == 0;
}

pub fn getAlignment(value: usize) u29 {
    const valueLow: u29 = @truncate(u29, value);
    const trailing = @ctz(u29, valueLow);
    return 1 << trailing;
}

/// Offsets the given pointer by the offset amount in bytes,
/// and casts the result to [*]T
pub fn adjustPtr(comptime T: type, ptr: var, offset: isize) [*]T {
    const base = @ptrToInt(ptr);
    const adjusted = base +% @bitCast(usize, offset);
    return @intToPtr([*]T, adjusted);
}

/// like ptrCast, but can remove const and doesn't validate alignment.
/// BEWARE: writing to data that is referenced from a const pointer
/// is UB in Zig, so even if you remove the const from a pointer,
/// you must not write to it.  This can still be useful for packing
/// opaque pointers into generic locations when you can ensure at
/// runtime that they will not be dereferenced or written to.
/// The user must also ensure that the input pointer is either aligned
/// according to the requirements of the result type, or will not be
/// dereferenced, since dereferencing an unaligned pointer is UB.
pub fn unsafePtrCast(comptime T: type, ptr: var) T {
    comptime {
        assert(@sizeOf(T) == @sizeOf(@typeOf(ptr)));
    }
    var result: T = undefined;
    @memcpy(@ptrCast([*]u8, &result), @ptrCast([*]const u8, &ptr), @sizeOf(T));
    return result;
}

/// Return ptrB - ptrA, in bytes.  Remember argument order with:
/// if a is before b, result is positive.
pub fn ptrDiff(ptrA: var, ptrB: var) isize {
    return @bitCast(isize, @ptrToInt(ptrB)) -% @bitCast(isize, @ptrToInt(ptrA));
}

pub fn alignPtrUp(comptime T: type, ptr: var, alignment: usize) T {
    const address = @ptrToInt(ptr);
    const aligned = alignUp(address, alignment);
    return @intToPtr(T, aligned);
}

/// Rounds up the given position to the next multiple of alignment.
/// alignment must be a power of two.
pub fn alignUp(pos: usize, alignment: usize) usize {
    assert(isPowerOfTwo(alignment));
    return mem.alignForward(pos, alignment);
}

/// Rounds up the given position to the next multiple of alignment.
/// alignment must be a power of two.
pub fn alignDown(pos: usize, alignment: usize) usize {
    assert(isPowerOfTwo(alignment));
    return mem.alignBackward(pos, alignment);
}

pub fn isPowerOfTwo(val: usize) bool {
    return val & (val - 1) == 0;
}
