const std = @import("std");
const assert = std.debug.assert;
const math = std.math;
const mem = std.mem;
const page_allocator = std.heap.direct_allocator;
const util = @import("util.zig");

// @todo: This API has a big cache associativity problem that will
// eventually rear its ugly head on Windows.  Most hot memory in the ECS
// is on directly mapped pages.  Chunks are 16k and pages are 4k, so this
// seems ok at first glance.  But on Windows, pages are aligned on 64k
// boundaries! This means that for any cache at least 64k large, we will
// only use a quarter of it!  Eventually we will need to allocate 64k
// at a time and sub-allocate chunks from it.

pub fn obtainAligned(size: usize, alignment: u29) ![]u8 {
    assert(util.isAligned(size, mem.page_size));
    assert(alignment >= mem.page_size);
    return try page_allocator.reallocFn(page_allocator, util.emptySlice(u8), 0, size, alignment);
}

pub fn obtain(size: usize) ![]u8 {
    return try obtainAligned(size, mem.page_size);
}

pub fn obtainAlignedAs(comptime T: type, size: usize, alignment: u29) !*T {
    assert(alignment >= @alignOf(T));
    const page = try obtainAligned(size, alignment);
    return @ptrCast(*T, @alignCast(@alignOf(T), page.ptr));
}

pub fn obtainAs(comptime T: type, size: usize) !*T {
    return try obtainAlignedAs(T, size, mem.page_size);
}

pub fn reallocAligned(page: []u8, newSize: usize, newAlign: u29) ![]u8 {
    assert(page.len == 0 or util.isAlignedPtr(page.ptr, mem.page_size));
    assert(util.isAligned(page.len, mem.page_size));
    assert(util.isAligned(newSize, mem.page_size));
    assert(newAlign >= mem.page_size);
    return try page_allocator.reallocFn(page_allocator, page, mem.page_size, newSize, newAlign);
}

pub fn shrinkAligned(page: []u8, newSize: usize, newAlign: u29) []u8 {
    assert(page.len == 0 or util.isAlignedPtr(page.ptr, mem.page_size));
    assert(util.isAligned(page.len, mem.page_size));
    assert(util.isAligned(newSize, mem.page_size));
    assert(newAlign >= mem.page_size);
    return page_allocator.shrinkFn(page_allocator, page, mem.page_size, newSize, newAlign);
}

pub fn release(page: []u8) void {
    assert(util.isAlignedPtr(page.ptr, mem.page_size));
    assert(util.isAligned(page.len, mem.page_size));
    _ = page_allocator.shrinkFn(page_allocator, page, mem.page_size, 0, 0);
}

pub fn releaseAs(page: var, size: usize) void {
    const basePtr = @ptrCast([*]u8, page);
    release(basePtr[0..size]);
}
