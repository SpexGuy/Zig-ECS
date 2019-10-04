const std = @import("std");
const util = @import("util.zig");
const chunk_layout = @import("chunk_layout.zig");
const assert = std.debug.assert;

const page_allocator = std.heap.direct_allocator;
const page_size = std.mem.page_size;
const chunk_size = page_size;

const sizes = [_]u32{
    64, 128, 256, 512, 1024, 2048,
};

comptime {
    assert(util.isPowerOfTwo(page_size));
    assert(util.isPowerOfTwo(chunk_size));
}

pub const BlockAllocator = struct {
    const Self = @This();

    blockSize: u32,
    dataPageNumBitmaskLongs: u32,
    dataPageSlots: u32,
    firstHeader: ?*IndexPageHeader = null,

    pub fn init(size: u32) Self {
        comptime {
            assert(@alignOf(DataPageHeader) == @alignOf(DataPageMask));
        }
        assert(util.isPowerOfTwo(size));
        assert(size >= 8);

        // this isn't perfect but it should be close enough.
        const maxChunkSize = chunk_size - @sizeOf(DataPageHeader) - @sizeOf(DataPageMask);
        const maxNumBlocks = maxChunkSize / size;
        const numBitmasks = (maxNumBlocks + 63) / 64;
        const chunkSize = chunk_size - @sizeOf(DataPageHeader) - numBitmasks * @sizeOf(DataPageMask);
        const numBlocks = chunkSize / size;

        return Self{
            .blockSize = size,
            .dataPageNumBitmaskLongs = numBitmasks,
            .dataPageSlots = numBlocks,
        };
    }

    const IndexPageHeader = struct {
        next: ?*IndexPageHeader = null,
        inUse: u32 = 0,
    };
    const IndexPageData = union(enum) {
        NumFreeSlots: u32,
        Data: *DataPage,
    };
    const IndexPage = chunk_layout.StaticChunk(IndexPageHeader, IndexPageData, page_size);

    fn allocFromIndexPage(self: Self, header: *IndexPageHeader) error{
        IndexPageFull,
        OutOfMemory,
    }![]u8 {
        // look for a data page with space
        const page = IndexPage.getFromHeader(header);
        const inUse = page.header.inUse;
        const freeSlotsArray = page.getValues(.NumFreeSlots);
        for (freeSlotsArray[0..inUse]) |numFreeSlots, i| {
            if (numFreeSlots > 0) {
                const dataPage = page.getValues(.Data)[i];
                // allocFromDataPage updates freeSlotsArray
                return self.allocFromDataPageMustBeFree(dataPage);
            }
        }
        // all used data pages are full, can we make a new one?
        const numSlots = IndexPage.layout.numItems;
        if (inUse < numSlots) {
            // newDataPage initializes freeSlotsArray
            const newPage = try self.newDataPage(&freeSlotsArray[inUse]); // OutOfMemory
            // link the new page
            const dataPtrArray = page.getValues(.Data);
            dataPtrArray[inUse] = newPage;
            page.header.inUse += 1;
            // alloc on the new page
            // allocFromDataPage updates freeSlotsArray
            return self.allocFromDataPageMustBeFree(newPage);
        }
        // otherwise all slots on this index page are in use
        return error.IndexPageFull;
    }

    fn alloc(self: *Self) error{OutOfMemory}![]u8 {
        var pCurrHeader: *?*IndexPageHeader = &self.firstHeader;
        var outOfMemory = false;
        while (pCurrHeader.* != null) {
            const currHeader = pCurrHeader.*.?;
            if (self.allocFromIndexPage(currHeader)) |slot| {
                return slot;
            } else |e| switch (e) {
                error.IndexPageFull => {},

                // All data pages on this index page are out of slots,
                // but the next page might have some free.
                // Mark that we can't alloc and keep looking.
                error.OutOfMemory => outOfMemory = true,
            }
            pCurrHeader = &currHeader.next;
        }

        if (outOfMemory)
            return error.OutOfMemory;

        const newPage = try self.newIndexPage();
        const newHeader = &newPage.header;
        pCurrHeader.* = newHeader;
        if (self.allocFromIndexPage(newHeader)) |slot| {
            return slot;
        } else |e| switch (e) {
            error.IndexPageFull => unreachable, // we just allocated this, it is empty.
            error.OutOfMemory => return error.OutOfMemory,
        }
    }

    fn allocFromDataPageMustBeFree(self: Self, page: *DataPage) []u8 {
        assert(page.header.indexNumFree.* > 0);
        const flagsList = self.getDataPageFlags(page);
        var block: u32 = 0;
        var index: u32 = 0;
        while (flagsList[index] == fullFlags) {
            index += 1;
            block += 64;
        }
        const flags = flagsList[index];
        const freeBlock = @clz(DataPageMask, ~flags);
        const mask = dataMask(63 - freeBlock);
        assert(freeBlock < 64);
        assert(flagsList[index] & mask == 0);
        flagsList[index] |= mask;
        page.header.indexNumFree.* -= 1;
        return self.getDataPageBlock(page, block + freeBlock);
    }

    fn newIndexPage(self: Self) !*IndexPage {
        const newPage = try std.heap.direct_allocator.create(IndexPage);
        newPage.header = IndexPageHeader{};
        return newPage;
    }

    fn newDataPage(self: Self, indexNumFree: *u32) !*DataPage {
        const newPage = try std.heap.direct_allocator.create(DataPage);

        // init page metadata
        newPage.header = DataPageHeader{
            .indexNumFree = indexNumFree,
        };
        const flags = self.getDataPageFlags(newPage);
        std.mem.set(DataPageMask, flags, 0);

        // mark pages in the bitmask that don't actually exist as allocated
        const extraBits = self.dataPageSlots % 64;
        if (extraBits != 0) {
            const firstInvalidBit = dataMask(64 - extraBits);
            flags[flags.len - 1] = firstInvalidBit - 1;
        }

        // set the number of free slots to all of them
        indexNumFree.* = self.dataPageSlots;

        return newPage;
    }

    fn getDataPageFlags(self: Self, page: *DataPage) []DataPageMask {
        const flagsBase = util.adjustPtr(DataPageMask, page, @sizeOf(DataPageHeader));
        return flagsBase[0..self.dataPageNumBitmaskLongs];
    }

    fn getDataPageChunk(self: Self, page: *DataPage) [*]u8 {
        const offset = @sizeOf(DataPageHeader) + self.dataPageNumBitmaskLongs * @sizeOf(DataPageMask);
        return util.adjustPtr(u8, page, offset);
    }

    fn getDataPageBlock(self: Self, page: *DataPage, block: u32) []u8 {
        assert(block < self.dataPageSlots);
        const chunkBase = self.getDataPageChunk(page);
        const blockBase = util.adjustPtr(u8, chunkBase, block * self.blockSize);
        return blockBase[0..self.blockSize];
    }

    fn dataMask(index: u32) DataPageMask {
        return @intCast(u64, 1) << @truncate(u6, index);
    }

    const DataPageMask = u64;
    const fullFlags = @bitCast(DataPageMask, @intCast(i64, -1));

    const dataPageCanary: u64 = 0xc0de1337cafed00d;
    const DataPageHeader = struct {
        canary: u64 = dataPageCanary,
        indexNumFree: *u32,
    };
    const DataPage = struct {
        header: DataPageHeader align(chunk_size),
        // following the header is an array of i64s, each representing a bitmask of blocks.
        // 1 is occupied, 0 is free.  blocks immediately follow these masks.
    };
};

test "block alloc" {
    var allocator = BlockAllocator.init(64);
    _ = try allocator.alloc();
    _ = try allocator.alloc();
    _ = try allocator.alloc();
}
