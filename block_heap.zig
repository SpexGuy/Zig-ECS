const std = @import("std");
const util = @import("util.zig");
const chunk_layout = @import("chunk_layout.zig");
const assert = std.debug.assert;

const page_allocator = std.heap.direct_allocator;

const sizes = [_]u32{
    64, 128, 256, 512, 1024, 2048,
};

const IndexPageHeader = struct {
    next: ?*IndexPageHeader = null,
    inUse: u32 = 0,
};
const IndexPageData = union(enum) {
    NumFreeSlots: u32,
    Data: *DataPage,
};
const IndexPageSchema = chunk_layout.SOASchema(IndexPageHeader, IndexPageData);
const IndexPage = IndexPageSchema.Chunk;

const dataPageCanary: u64 = 0xc0de1337cafed00d;
const DataPageHeader = struct {
    canary: u64 = dataPageCanary,
    indexNumFree: *u32,
};
const DataPage = struct {
    header: DataPageHeader,
    // following the header is an array of i64s, each representing a bitmask of blocks.
    // 1 is occupied, 0 is free.  blocks immediately follow these masks.
};

const DataPageMask = u64;
const fullFlags = @bitCast(DataPageMask, @intCast(i64, -1));
fn dataMask(index: u32) DataPageMask {
    return @intCast(u64, 1) << @truncate(u6, index);
}

comptime {
    assert(@alignOf(DataPageHeader) == @alignOf(DataPageMask));
}

pub const BlockHeap = struct {
    const Self = @This();

    pageSize: u32,
    indexPageLayout: IndexPageSchema,
    allocators: [sizes.len]BlockAllocator,

    pub fn init(pageSize: u32) Self {
        assert(util.isPowerOfTwo(pageSize));

        var newHeap = Self{
            .pageSize = pageSize,
            .indexPageLayout = IndexPageSchema.layout(pageSize),
            .allocators = undefined, // we'll fill this in next
        };

        for (sizes) |blockSize, i| {
            newHeap.allocators[i] = BlockAllocator.init(pageSize, blockSize);
        }

        return newHeap;
    }

    fn allocFromAllocator(self: Self, allocator: *BlockAllocator) error{OutOfMemory}![]u8 {
        var pCurrHeader: *?*IndexPageHeader = &allocator.firstHeader;
        var outOfMemory = false;
        while (pCurrHeader.* != null) {
            const currHeader = pCurrHeader.*.?;
            if (self.allocFromIndexPage(allocator, currHeader)) |slot| {
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
        if (self.allocFromIndexPage(allocator, newHeader)) |slot| {
            return slot;
        } else |e| switch (e) {
            error.IndexPageFull => unreachable, // we just allocated this, it is empty.
            error.OutOfMemory => return error.OutOfMemory,
        }
    }

    fn allocFromIndexPage(self: Self, allocator: *BlockAllocator, header: *IndexPageHeader) error{
        IndexPageFull,
        OutOfMemory,
    }![]u8 {
        // look for a data page with space
        const page = self.indexPageLayout.getChunkFromHeader(header);
        const inUse = page.header.inUse;
        const freeSlotsArray = self.indexPageLayout.getValues(page, .NumFreeSlots);
        const dataPtrArray = self.indexPageLayout.getValues(page, .Data);
        for (freeSlotsArray[0..inUse]) |numFreeSlots, i| {
            if (numFreeSlots > 0) {
                // allocFromDataPage updates freeSlotsArray
                return allocator.allocFromDataPageMustBeFree(dataPtrArray[i]);
            }
        }
        // all used data pages are full, can we make a new one?
        const numSlots = self.indexPageLayout.layout.numItems;
        if (inUse < numSlots) {
            // newDataPage initializes freeSlotsArray
            const newPage = try self.newDataPage(allocator, &freeSlotsArray[inUse]); // OutOfMemory
            // link the new page
            dataPtrArray[inUse] = newPage;
            page.header.inUse += 1;
            // alloc on the new page
            // allocFromDataPage updates freeSlotsArray
            return allocator.allocFromDataPageMustBeFree(newPage);
        }
        // otherwise all slots on this index page are in use
        return error.IndexPageFull;
    }

    fn newIndexPage(self: Self) !*IndexPage {
        // @todo: This is wrong, allocate the correct size and alignment.
        const newPage = try std.heap.direct_allocator.create(IndexPage);
        newPage.header = IndexPageHeader{};
        return newPage;
    }

    fn newDataPage(self: Self, allocator: *BlockAllocator, indexNumFree: *u32) !*DataPage {
        // @todo: This is wrong, allocate the correct size and alignment.
        const newPage = try std.heap.direct_allocator.create(DataPage);
        allocator.initDataPage(newPage, indexNumFree);
        return newPage;
    }
};

pub const BlockAllocator = struct {
    const Self = @This();

    blockSize: u32,
    dataPageNumBitmaskLongs: u32,
    dataPageSlots: u32,
    firstHeader: ?*IndexPageHeader = null,

    pub fn init(pageSize: u32, inBlockSize: u32) Self {
        assert(util.isPowerOfTwo(inBlockSize));
        assert(inBlockSize >= 8);

        // this isn't perfect but it should be close enough.
        const maxChunkSize = pageSize - @sizeOf(DataPageHeader) - @sizeOf(DataPageMask);
        const maxNumBlocks = maxChunkSize / inBlockSize;
        const numBitmasks = (maxNumBlocks + 63) / 64;
        const chunkSize = pageSize - @sizeOf(DataPageHeader) - numBitmasks * @sizeOf(DataPageMask);
        const numBlocks = chunkSize / inBlockSize;

        return Self{
            .blockSize = inBlockSize,
            .dataPageNumBitmaskLongs = numBitmasks,
            .dataPageSlots = numBlocks,
        };
    }

    fn initDataPage(self: Self, newPage: *DataPage, indexNumFree: *u32) void {
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
};

test "block alloc" {
    var allocator = BlockHeap.init(4096);
    _ = try allocator.allocFromAllocator(&allocator.allocators[0]);
    _ = try allocator.allocFromAllocator(&allocator.allocators[0]);
    _ = try allocator.allocFromAllocator(&allocator.allocators[0]);
}
