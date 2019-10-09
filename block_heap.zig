const std = @import("std");
const util = @import("util.zig");
const chunk_layout = @import("chunk_layout.zig");
const pages = @import("pages.zig");
const assert = std.debug.assert;
const testing = std.testing;
const mem = std.mem;
const math = std.math;

const sizes = [_]u32{
    16,   32,   64,   128,  256,   512,
    1024, 2048, 4096, 8192, 16384,
};

const indexPageSize = mem.page_size;
const dataPageSize = 64 * 1024;
const maxBlockSize = sizes[sizes.len - 1];
const smallestBlockSize = sizes[0];

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

const dataPageCanary: u64 = 0x5ca1ab1eb0a710ad;
const fakeDataPageCanary: u64 = 0x1005e1eaf0ddba11;
const DataPageHeader = struct {
    canary: u64 = dataPageCanary,
    indexNumFree: *u32,
    blockAllocator: *BlockAllocator,
};
const DataPage = struct {
    header: DataPageHeader,
    // following the header is an array of i64s, each representing a bitmask of blocks.
    // 1 is occupied, 0 is free.  blocks immediately follow these masks.
};

const DataPageMask = u64;
const fullFlags = @bitCast(DataPageMask, @intCast(i64, -1));
fn dataMask(index: u32) DataPageMask {
    return @intCast(u64, 1) << @truncate(u6, 63 - index);
}

comptime {
    assert(@alignOf(DataPageHeader) == @alignOf(DataPageMask));
}

pub const BlockHeap = struct {
    const Self = @This();

    allocator: mem.Allocator,
    indexPageLayout: IndexPageSchema,
    blockAllocators: [sizes.len]BlockAllocator,

    pub fn init() Self {
        var newHeap = Self{
            .allocator = mem.Allocator{
                .reallocFn = realloc,
                .shrinkFn = shrink,
            },
            .indexPageLayout = IndexPageSchema.layout(indexPageSize),
            .blockAllocators = undefined, // we'll fill this in next
        };

        for (sizes) |blockSize, i| {
            newHeap.blockAllocators[i] = BlockAllocator.init(blockSize);
        }

        return newHeap;
    }

    fn realloc(
        allocator: *mem.Allocator,
        old_mem: []u8,
        min_old_alignment: u29,
        new_byte_count: usize,
        new_alignment: u29,
    ) error{OutOfMemory}![]u8 {
        if (new_byte_count == 0) return util.emptySlice(u8);
        const self = @fieldParentPtr(Self, "allocator", allocator);
        if (old_mem.len == 0) {
            // new allocation
            if (self.shouldDirectAllocate(new_byte_count, new_alignment)) {
                const directSize = self.toDirectAllocationSize(new_byte_count);
                const directAlignment = math.max(new_alignment, dataPageSize);
                const newDirectMem = try pages.obtainAligned(directSize, directAlignment);
                return newDirectMem[0..new_byte_count];
            } else {
                const block = try self.alignedBlockAlloc(new_byte_count, new_alignment);
                return block[0..new_byte_count];
            }
        } else {
            // realloc an existing allocation
            if (self.isDirectAllocation(old_mem)) {
                assert(self.shouldDirectAllocate(new_byte_count, new_alignment));
                const oldFullMem = self.toDirectAllocation(old_mem);
                const newMemSize = self.toDirectAllocationSize(new_byte_count);
                const directAlignment = math.max(new_alignment, dataPageSize);
                const newFullMem = try pages.reallocAligned(oldFullMem, newMemSize, directAlignment);
                return newFullMem[0..new_byte_count];
            } else {
                const oldSize = math.max(old_mem.len, min_old_alignment);
                const newSize = math.max(new_byte_count, new_alignment);
                if (newSize <= oldSize) {
                    return shrink(allocator, old_mem, min_old_alignment, new_byte_count, new_alignment);
                }
                if (self.shouldDirectAllocate(new_byte_count, new_alignment)) {
                    const directSize = self.toDirectAllocationSize(new_byte_count);
                    const directAlignment = math.max(new_alignment, dataPageSize);
                    const newDirectMem = try pages.obtainAligned(directSize, directAlignment);
                    @memcpy(newDirectMem.ptr, old_mem.ptr, math.min(old_mem.len, new_byte_count));
                    self.freeBlock(old_mem.ptr);
                    return newDirectMem[0..new_byte_count];
                } else {
                    // check if we can fit it in the existing allocation
                    const oldBlockSize = self.getBlockSize(old_mem.len, min_old_alignment);
                    if (new_byte_count <= oldBlockSize and util.isAlignedPtr(old_mem.ptr, new_alignment)) {
                        // this slice is fine
                        return old_mem.ptr[0..new_byte_count];
                    }
                    // if we get here, we need a new allocation
                    const newBlockSize = self.getBlockSize(new_byte_count, new_alignment);
                    const blockAllocator = self.getBlockAllocator(newBlockSize);
                    const newMem = try self.allocFromAllocator(blockAllocator);
                    @memcpy(newMem.ptr, old_mem.ptr, math.min(old_mem.len, new_byte_count));
                    self.freeBlock(old_mem.ptr);
                    return newMem[0..new_byte_count];
                }
            }
        }
    }

    fn shrink(
        allocator: *mem.Allocator,
        old_mem: []u8,
        min_old_alignment: u29,
        new_byte_count: usize,
        new_alignment: u29,
    ) []u8 {
        if (old_mem.len == 0)
            return util.emptySlice(u8);
        const self = @fieldParentPtr(Self, "allocator", allocator);
        if (self.isDirectAllocation(old_mem)) {
            const fullOldChunk = self.toDirectAllocation(old_mem);
            if (new_byte_count == 0 or self.shouldDirectAllocate(new_byte_count, new_alignment)) {
                const newDirectSize = self.toDirectAllocationSize(new_byte_count);
                const newDirectAlignment = math.max(dataPageSize, new_alignment);
                const newDirectPage = pages.shrinkAligned(fullOldChunk, newDirectSize, newDirectAlignment);
                return newDirectPage[0..new_byte_count];
            } else {
                // moving from direct allocation to paged alloc
                if (self.alignedBlockAlloc(new_byte_count, new_alignment)) |newMem| {
                    // copy memory
                    @memcpy(newMem.ptr, old_mem.ptr, new_byte_count);
                    // free the old chunk
                    pages.release(fullOldChunk);
                    // truncate the result down to the requested size
                    return newMem[0..new_byte_count];
                } else |err| {
                    // move the allocation to an aligned point in the chunk,
                    // but leave space for the header.  Set the header to a fake page,
                    // then return the aligned block.  Don't overlap the new memory
                    // with the old memory so that memcpy is safe.  We can do this because
                    // we know that new_byte_count is less than half of the data page size.
                    var offset: usize = math.max(@sizeOf(DataPageHeader), new_byte_count);
                    offset = util.alignUp(offset, new_alignment);
                    const newNeededSize = offset + new_byte_count;
                    const newDirectSize = self.toDirectAllocationSize(newNeededSize);
                    assert(newDirectSize <= fullOldChunk.len);

                    // couldn't do an aligned alloc
                    // we will recognize this as a block alloc in the future,
                    // so we need to trick this into being an alloc.
                    // If the old memory is more than a data page, we need to realloc it
                    // onto a data page, to ensure correct tracking.
                    assert(fullOldChunk.len >= dataPageSize);
                    var newChunk = fullOldChunk;
                    if (newDirectSize < fullOldChunk.len) {
                        newChunk = pages.shrinkAligned(old_mem, newDirectSize, dataPageSize);
                    }

                    assert(util.isAlignedPtr(newChunk.ptr, dataPageSize));

                    const newDataPtr = util.adjustPtr(u8, newChunk.ptr, @intCast(isize, offset));
                    @memcpy(newDataPtr, newChunk.ptr, new_byte_count);

                    const header = @ptrCast(*DataPageHeader, @alignCast(dataPageSize, newChunk.ptr));
                    header.* = DataPageHeader{
                        .canary = fakeDataPageCanary,
                        .indexNumFree = @intToPtr(*u32, newDirectSize),
                        .blockAllocator = undefined,
                    };

                    return newDataPtr[0..new_byte_count];
                }
            }
        } else {
            if (new_byte_count == 0) {
                self.freeBlock(old_mem.ptr);
                return util.emptySlice(u8);
            }

            // this is a block allocation
            const old_block_size = self.getBlockSize(old_mem.len, min_old_alignment);
            const new_block_size = self.getBlockSize(new_byte_count, new_alignment);
            assert(new_block_size <= old_block_size);

            var newBlock = old_mem.ptr[0..old_block_size];
            if (new_block_size < old_block_size) {
                // try to realloc in smaller allocator.
                const newBlockAllocator = self.getBlockAllocator(new_block_size);
                if (self.allocFromAllocator(newBlockAllocator)) |block| {
                    @memcpy(block.ptr, old_mem.ptr, new_byte_count);
                    self.freeBlock(old_mem.ptr);
                    newBlock = block;
                } else |err| {}
            }

            return newBlock[0..new_byte_count];
        }
    }

    fn isDirectAllocation(self: Self, allocation: []u8) bool {
        return util.isAlignedPtr(allocation.ptr, dataPageSize);
    }

    fn toDirectAllocationSize(self: Self, size: usize) usize {
        return util.alignUp(size, mem.page_size);
    }

    fn toDirectAllocation(self: Self, parentAlloc: []u8) []u8 {
        const actualSize = self.toDirectAllocationSize(parentAlloc.len);
        // use ptr here to avoid the bounds check, since we are widening the slice.
        return parentAlloc.ptr[0..actualSize];
    }

    fn shouldDirectAllocate(self: Self, size: usize, alignment: u29) bool {
        const blockSize = math.max(size, alignment);
        return blockSize > maxBlockSize;
    }

    fn getBlockSize(self: Self, size: usize, alignment: u29) u32 {
        assert(size > 0);
        var blockSize: u32 = math.max(@intCast(u32, size), alignment);
        blockSize = util.roundUpToPowerOfTwo(blockSize);
        blockSize = math.max(blockSize, smallestBlockSize);
        assert(blockSize <= maxBlockSize);
        return blockSize;
    }

    fn alignedBlockAlloc(self: *Self, size: usize, alignment: u29) ![]u8 {
        const blockSize = self.getBlockSize(size, alignment);
        const allocator = self.getBlockAllocator(blockSize);
        return self.allocFromAllocator(allocator);
    }

    fn getBlockAllocator(self: *Self, blockSize: u32) *BlockAllocator {
        const index: u32 = math.log2_int(u32, blockSize) - (comptime math.log2_int(u32, smallestBlockSize));
        return &self.blockAllocators[index];
    }

    fn freeBlock(self: Self, ptrInBlock: [*]u8) void {
        const address = @ptrToInt(ptrInBlock);
        const headerAddress = address & ~(usize(dataPageSize) - 1);
        const page = @intToPtr(*DataPage, headerAddress);
        switch (page.header.canary) {
            dataPageCanary => {
                const blockAllocator = page.header.blockAllocator;
                const blockSize = blockAllocator.blockSize;
                const chunkStart = self.getDataPageChunk(blockAllocator, page);
                const chunkOffset = @intCast(u32, util.ptrDiff(chunkStart, ptrInBlock));
                assert(chunkOffset % blockSize == 0);
                var chunkIndex: u32 = chunkOffset / blockSize;
                var flagsIndex: u32 = 0;
                while (chunkIndex >= 64) {
                    chunkIndex -= 64;
                    flagsIndex += 1;
                }
                const flags = self.getDataPageFlags(blockAllocator, page);
                const bit = dataMask(chunkIndex);
                flags[flagsIndex] &= ~bit;
                page.header.indexNumFree.* += 1;
            },
            fakeDataPageCanary => {
                const mappedLength = @ptrToInt(page.header.indexNumFree);
                const untypedPage = @ptrCast([*]u8, page);
                const fullPage = untypedPage[0..mappedLength];
                pages.release(fullPage);
            },
            else => unreachable,
        }
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
                return self.allocFromDataPageMustBeFree(allocator, dataPtrArray[i]);
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
            return self.allocFromDataPageMustBeFree(allocator, newPage);
        }
        // otherwise all slots on this index page are in use
        return error.IndexPageFull;
    }

    fn newIndexPage(self: Self) !*IndexPage {
        const newPage = try pages.obtainAs(IndexPage, indexPageSize);
        newPage.* = IndexPage{
            .header = IndexPageHeader{},
        };
        return newPage;
    }

    fn newDataPage(self: Self, allocator: *BlockAllocator, indexNumFree: *u32) !*DataPage {
        const newPage = try pages.obtainAlignedAs(DataPage, dataPageSize, dataPageSize);
        self.initDataPage(allocator, newPage, indexNumFree);
        return newPage;
    }

    fn initDataPage(self: Self, allocator: *BlockAllocator, newPage: *DataPage, indexNumFree: *u32) void {
        // init page metadata
        newPage.header = DataPageHeader{
            .indexNumFree = indexNumFree,
            .blockAllocator = allocator,
        };
        const flags = self.getDataPageFlags(allocator, newPage);
        mem.set(DataPageMask, flags, 0);

        // mark pages in the bitmask that don't actually exist as allocated
        const extraBits = allocator.dataPageSlots % 64;
        if (extraBits != 0) {
            const firstInvalidBit = dataMask(extraBits - 1);
            flags[flags.len - 1] = firstInvalidBit - 1;
        }

        // set the number of free slots to all of them
        indexNumFree.* = allocator.dataPageSlots;
    }

    fn allocFromDataPageMustBeFree(self: Self, allocator: *BlockAllocator, page: *DataPage) []u8 {
        assert(page.header.indexNumFree.* > 0);
        const flagsList = self.getDataPageFlags(allocator, page);
        var block: u32 = 0;
        var index: u32 = 0;
        while (flagsList[index] == fullFlags) {
            index += 1;
            block += 64;
        }
        const flags = flagsList[index];
        const freeIndex = @clz(DataPageMask, ~flags);
        const mask = dataMask(freeIndex);
        assert(freeIndex < 64);
        assert(flagsList[index] & mask == 0);
        flagsList[index] |= mask;
        page.header.indexNumFree.* -= 1;
        return self.getDataPageBlock(allocator, page, block + freeIndex);
    }

    fn getDataPageFlags(self: Self, allocator: *BlockAllocator, page: *DataPage) []DataPageMask {
        const flagsBase = util.adjustPtr(DataPageMask, page, @sizeOf(DataPageHeader));
        return flagsBase[0..allocator.dataPageNumBitmaskLongs];
    }

    fn getDataPageChunk(self: Self, allocator: *BlockAllocator, page: *DataPage) [*]u8 {
        const offset = dataPageSize - allocator.dataPageSlots * allocator.blockSize;
        return util.adjustPtr(u8, page, offset);
    }

    fn getDataPageBlock(self: Self, allocator: *BlockAllocator, page: *DataPage, block: u32) []u8 {
        assert(block < allocator.dataPageSlots);
        const chunkBase = self.getDataPageChunk(allocator, page);
        const blockBase = util.adjustPtr(u8, chunkBase, block * allocator.blockSize);
        return blockBase[0..allocator.blockSize];
    }
};

pub const BlockAllocator = struct {
    const Self = @This();

    blockSize: u32,
    dataPageNumBitmaskLongs: u32,
    dataPageSlots: u32,
    firstHeader: ?*IndexPageHeader = null,

    pub fn init(inBlockSize: u32) Self {
        assert(util.isPowerOfTwo(inBlockSize));
        assert(inBlockSize >= 8);

        // this isn't perfect but it should be close enough.
        const maxChunkSize = dataPageSize - @sizeOf(DataPageHeader) - @sizeOf(DataPageMask);
        const maxNumBlocks = maxChunkSize / inBlockSize;
        const numBitmasks = (maxNumBlocks + 63) / 64;
        const chunkSize = dataPageSize - @sizeOf(DataPageHeader) - numBitmasks * @sizeOf(DataPageMask);
        const numBlocks = chunkSize / inBlockSize;

        return Self{
            .blockSize = inBlockSize,
            .dataPageNumBitmaskLongs = numBitmasks,
            .dataPageSlots = numBlocks,
        };
    }
};

test "block alloc" {
    var allocator = BlockHeap.init();
    const a = try allocator.allocator.alloc(u8, 64);
    const b = try allocator.allocator.alloc(u8, 33);
    const c = try allocator.allocator.alloc(u8, 64);
    allocator.allocator.free(b);
    const d = try allocator.allocator.alloc(u8, 64);
    assert(d.ptr == b.ptr);

    try @import("test_allocator.zig").testAll(&allocator.allocator);
}
