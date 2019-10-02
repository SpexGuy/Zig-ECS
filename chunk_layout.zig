const std = @import("std");
const assert = std.debug.assert;
const util = @import("util.zig");

pub const TypeLayout = struct {
    const Self = @This();

    alignment: u32,
    size: u32,

    pub fn init(comptime T: type) Self {
        return Self{
            .alignment = @alignOf(T),
            .size = @sizeOf(T),
        };
    }
};

pub fn ChunkLayout(comptime n: u32) type {
    return struct {
        numItems: u32,
        offsets: [n]u32,
    };
}

pub fn layoutStaticChunk(chunkSize: u32, headerSize: u32, comptime types: []const TypeLayout) ChunkLayout(types.len) {
    var ret: ChunkLayout(types.len) = undefined;
    ret.numItems = layoutChunk(chunkSize, headerSize, types, ret.offsets[0..]);
    return ret;
}

/// Compute offsets to SOA layout the provided list of types
/// within a chunk of the given size.  The alignment of the chunk
/// must be larger than the largest alignment of any component.
/// Returns the number of items that fit in the chunk, and sets
/// the values of outOffsets to the offset that corresponds to
/// each type.  Offsets are from the beginning of the chunk.
/// Chunk size includes the header size.
pub fn layoutChunk(chunkSize: u32, headerSize: u32, types: []const TypeLayout, outOffsets: []u32) u32 {
    assert(headerSize < chunkSize);
    assert(types.len == outOffsets.len);
    assert(types.len != 0);

    // calculate the maximum number of items we could fit ignoring alignment.
    var totalSize: u32 = 0;
    for (types) |info| {
        totalSize += info.size;
    }
    const maxNum = (chunkSize - headerSize) / totalSize;

    // run aligned layout, reduce number of items until it fits.
    var numItems = maxNum;
    while (numItems > 0) {
        const neededSize = layoutItems(numItems, headerSize, types, outOffsets);
        if (neededSize <= chunkSize) break;
        numItems -= 1;
    }

    // @todo: This is maybe a reasonable case, we might need to handle it.
    assert(numItems > 0);
    return numItems;
}

/// Compute offsets to SOA layout the given number of items
/// alongside a header of a given size.  Returns the total size
/// needed to lay out this many items.
fn layoutItems(numItems: u32, headerSize: u32, types: []const TypeLayout, outOffsets: []u32) u32 {
    var pos = headerSize;
    for (types) |info, i| {
        pos = util.alignUp(pos, info.alignment);
        outOffsets[i] = pos;
        pos += info.size * numItems;
    }
    return pos;
}
