const std = @import("std");
const assert = std.debug.assert;
const pageAlloc = std.heap.direct_allocator;
const pageSize = std.mem.page_size;

const LinkedChunks = struct {
    const Self = @This();

    itemSize: u32,
    itemAlign: u32,
    firstItemOffset: u32,
    itemsPerChunk: u32,
    numChunks: u32 = 0,
    firstChunk: ?*Header = null,
    lastChunk: ?*Header = null,

    const Header = struct {
        next: ?*Header,
    };

    pub fn init(comptime T: type) Self {
        const size = @sizeOf(T);
        const alignment = @alignOf(T);
        const alignMask = alignment - 1;
        const firstOffset = (@sizeOf(Header) + alignMask) & alignMask;
        const remain: i32 = pageSize - firstOffset;
        const numSlots = remain / size;
        comptime {
            assert(remain > 0);
            assert(numSlots > 0);
        }
        return Self{
            .itemSize = size,
            .itemAlign = alignment,
            .firstItemOffset = firstOffset,
            .itemsPerChunk = numSlots,
        };
    }

    pub fn getDataRawPtr(self: Self, pHeader: *Header) [*]u8 {
        return @ptrCast([*]u8, pHeader) + self.firstItemOffset;
    }

    pub fn getDataRawSlice(self: Self, pHeader: *Header) []u8 {
        const rawPtr = getDataRawPtr(self, pHeader);
        return rawPtr[0 .. itemsPerChunk * itemSize];
    }

    pub fn getDataPtr(self: Self, comptime T: type, pHeader: *Header) [*]T {
        assert(@sizeOf(T) == self.itemSize);
        const raw = getDataRawPtr(self, pHeader);
        const typedRaw = @ptrCast([*]T, raw);
        return typedRaw[0..self.itemsPerChunk];
    }

    pub fn getItemRawPtr(self: Self, index: u32) [*]u8 {
        const chunkIndex = index / self.itemsPerChunk;
        const slotIndex = index % self.itemsPerChunk;
        var chunksLeft = chunkIndex;
        var pChunk = self.firstChunk;
        while (chunksLeft) {
            pChunk = pChunk.?.next;
            chunksLeft -= 1;
        }
        const chunkData = getDataRawPtr(self, pChunk.?);
        return chunkData + slotIndex * itemSize;
    }

    pub fn getItemRawSlice(self: Self, index: u32) []u8 {
        const rawPtr = getItemRawPtr(self, index);
        return rawPtr[0..itemSize];
    }

    pub fn getItemPtr(self: Self, comptime T: type, index: u32) *T {
        assert(@sizeOf(T) == self.itemSize);
        return @ptrCast(*T, getItemRawPtr(self, T, index));
    }

    pub fn addChunk(self: Self) void {
        // TODO
    }
};

test "chunk list" {
    const list = LinkedChunks.init(*u32);
    std.debug.warn("itemsPerChunk = {}\n", list.itemsPerChunk);
}
