const std = @import("std");
const util = @import("util.zig");
const chunk_layout = @import("chunk_layout.zig");
const assert = std.debug.assert;
const testing = std.testing;
const mem = std.mem;
const math = std.math;

const page_allocator = std.heap.direct_allocator;

const sizes = [_]u32{
    64, 128, 256, 512, 1024, 2048,
};

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
    pageSize: u29,
    indexPageLayout: IndexPageSchema,
    blockAllocators: [sizes.len]BlockAllocator,

    pub fn init(pageSize: u32) Self {
        assert(util.isPowerOfTwo(pageSize));

        var newHeap = Self{
            .allocator = mem.Allocator{
                .reallocFn = realloc,
                .shrinkFn = shrink,
            },
            .pageSize = @intCast(u29, pageSize),
            .indexPageLayout = IndexPageSchema.layout(pageSize),
            .blockAllocators = undefined, // we'll fill this in next
        };

        for (sizes) |blockSize, i| {
            newHeap.blockAllocators[i] = BlockAllocator.init(pageSize, blockSize);
        }

        return newHeap;
    }

    fn realloc(
        allocator: *mem.Allocator,
        old_mem: []u8,
        old_alignment: u29,
        new_byte_count: usize,
        new_alignment: u29,
    ) error{OutOfMemory}![]u8 {
        if (new_byte_count == 0) return util.emptySlice(u8);
        const self = @fieldParentPtr(Self, "allocator", allocator);
        if (old_mem.len == 0) {
            // new allocation
            if (self.isDirectAllocation(new_byte_count, new_alignment)) {
                const directSize = self.toDirectAllocationSize(new_byte_count);
                const newDirectMem = try page_allocator.reallocFn(page_allocator, old_mem, old_alignment, directSize, self.pageSize);
                return newDirectMem[0..new_byte_count];
            } else {
                const block = try self.alignedBlockAlloc(new_byte_count, new_alignment);
                return block[0..new_byte_count];
            }
        } else {
            // realloc an existing allocation
            if (self.isDirectAllocation(old_mem.len, old_alignment)) {
                assert(self.isDirectAllocation(new_byte_count, new_alignment));
                const oldFullMem = self.toDirectAllocation(old_mem);
                const newMemSize = self.toDirectAllocationSize(new_byte_count);
                const newFullMem = try page_allocator.reallocFn(page_allocator, oldFullMem, old_alignment, newMemSize, new_alignment);
                return newFullMem[0..new_byte_count];
            } else {
                const oldSize = math.max(old_mem.len, old_alignment);
                const newSize = math.max(new_byte_count, new_alignment);
                if (newSize <= oldSize) {
                    return shrink(allocator, old_mem, old_alignment, new_byte_count, new_alignment);
                }
                if (self.isDirectAllocation(new_byte_count, new_alignment)) {
                    const directSize = self.toDirectAllocationSize(new_byte_count);
                    const newDirectMem = try self.allocDirectPage(directSize, new_alignment);
                    @memcpy(newDirectMem.ptr, old_mem.ptr, old_mem.len);
                    self.freeBlock(old_mem.ptr);
                    return newDirectMem[0..new_byte_count];
                } else {
                    // check if we can fit it in the existing allocation
                    const oldBlockSize = self.getBlockSize(old_mem.len, old_alignment);
                    if (new_byte_count <= oldBlockSize and util.isAlignedPtr(old_mem.ptr, new_alignment)) {
                        // this slice is fine
                        return old_mem.ptr[0..new_byte_count];
                    }
                    // if we get here, we need a new allocation
                    const newBlockSize = self.getBlockSize(new_byte_count, new_alignment);
                    const blockAllocator = self.getBlockAllocator(newBlockSize);
                    const newMem = try self.allocFromAllocator(blockAllocator);
                    @memcpy(newMem.ptr, old_mem.ptr, old_mem.len);
                    self.freeBlock(old_mem.ptr);
                    return newMem[0..new_byte_count];
                }
            }
        }
    }

    fn shrink(
        allocator: *mem.Allocator,
        old_mem: []u8,
        old_alignment: u29,
        new_byte_count: usize,
        new_alignment: u29,
    ) []u8 {
        if (old_mem.len == 0)
            return util.emptySlice(u8);
        const self = @fieldParentPtr(Self, "allocator", allocator);
        if (self.isDirectAllocation(old_mem.len, old_alignment)) {
            const fullOldChunk = self.toDirectAllocation(old_mem);
            if (new_byte_count == 0 or self.isDirectAllocation(new_byte_count, new_alignment)) {
                const newDirectSize = self.toDirectAllocationSize(new_byte_count);
                const newDirectPage = page_allocator.shrinkFn(
                    page_allocator,
                    fullOldChunk,
                    old_alignment,
                    newDirectSize,
                    new_alignment,
                );
                return newDirectPage[0..new_byte_count];
            } else {
                // moving from direct allocation to paged alloc
                if (self.alignedBlockAlloc(new_byte_count, new_alignment)) |newMem| {
                    // copy memory
                    @memcpy(newMem.ptr, old_mem.ptr, new_byte_count);
                    // free the old chunk
                    _ = page_allocator.shrinkFn(page_allocator, fullOldChunk, old_alignment, 0, 0);
                    // truncate the result down to the requested size
                    return newMem[0..new_byte_count];
                } else |err| {
                    // couldn't do an aligned alloc
                    // we will recognize this as a block alloc in the future,
                    // so we need to trick this into being an alloc.
                    // If the old memory is more than a page, we need to realloc it
                    // onto a page, to ensure correct tracking.
                    var newChunk = fullOldChunk;
                    if (old_mem.len > self.pageSize or old_alignment > self.pageSize) {
                        newChunk = page_allocator.shrinkFn(
                            page_allocator,
                            old_mem,
                            old_alignment,
                            self.pageSize,
                            self.pageSize,
                        );
                    }

                    // move the allocation to an aligned point in the chunk,
                    // but leave space for the header.  Set the header to a fake page,
                    // then return the aligned block.
                    var offset: usize = @sizeOf(DataPageHeader);
                    offset = util.alignUp(offset, new_alignment);
                    assert(offset + new_byte_count <= self.pageSize);

                    const newDataPtr = util.adjustPtr(u8, newChunk.ptr, @intCast(isize, offset));
                    @memcpy(newDataPtr, newChunk.ptr, new_byte_count);

                    const header = @ptrCast(*DataPageHeader, @alignCast(4096, newChunk.ptr));
                    header.* = DataPageHeader{
                        .canary = fakeDataPageCanary,
                        .indexNumFree = undefined,
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
            const old_block_size = self.getBlockSize(old_mem.len, old_alignment);
            const new_block_size = self.getBlockSize(new_byte_count, new_alignment);
            assert(new_block_size <= old_block_size);

            var newBlock = old_mem;
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

    fn toDirectAllocationSize(self: Self, size: usize) usize {
        return util.alignUp(size, self.pageSize);
    }

    fn toDirectAllocation(self: Self, parentAlloc: []u8) []u8 {
        const actualSize = self.toDirectAllocationSize(parentAlloc.len);
        // use ptr here to avoid the bounds check, since we are widening the slice.
        return parentAlloc.ptr[0..actualSize];
    }

    fn isDirectAllocation(self: Self, size: usize, alignment: u29) bool {
        const blockSize = math.max(size, alignment);
        return blockSize > self.maxBlockSize();
    }

    fn maxBlockSize(self: Self) u32 {
        return self.pageSize / 4;
    }

    fn getBlockSize(self: Self, size: usize, alignment: u29) u32 {
        assert(size > 0);
        var blockSize: u32 = math.max(@intCast(u32, size), alignment);
        blockSize = util.roundUpToPowerOfTwo(blockSize);
        blockSize = math.max(blockSize, smallestBlockSize);
        assert(blockSize <= self.maxBlockSize());
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
        const headerAddress = address & ~(u64(self.pageSize) - 1);
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
                while (chunkIndex > 64) {
                    chunkIndex -= 64;
                    flagsIndex += 1;
                }
                const flags = self.getDataPageFlags(blockAllocator, page);
                const bit = dataMask(chunkIndex);
                flags[flagsIndex] &= ~bit;
                page.header.indexNumFree.* += 1;
            },
            fakeDataPageCanary => {
                const untypedPage = @ptrCast([*]u8, page);
                const fullPage = untypedPage[0..self.pageSize];
                _ = page_allocator.shrinkFn(page_allocator, fullPage, self.pageSize, 0, 0);
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
        // @todo: This is wrong, allocate the correct size and alignment.
        const newPage = try std.heap.direct_allocator.create(IndexPage);
        newPage.header = IndexPageHeader{};
        return newPage;
    }

    fn newDataPage(self: Self, allocator: *BlockAllocator, indexNumFree: *u32) !*DataPage {
        // @todo: This is wrong, allocate the correct size and alignment.
        const newPage = try std.heap.direct_allocator.create(DataPage);
        self.initDataPage(allocator, newPage, indexNumFree);
        return newPage;
    }

    fn allocDirectPage(self: Self, size: usize, alignment: u29) ![]u8 {
        assert(util.isAligned(size, self.pageSize));
        assert(util.isPowerOfTwo(alignment));
        return try page_allocator.reallocFn(page_allocator, util.emptySlice(u8), 0, size, alignment);
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
        const offset = self.pageSize - allocator.dataPageSlots * allocator.blockSize;
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
};

test "block alloc" {
    var allocator = BlockHeap.init(4096);
    const a = try allocator.allocator.alloc(u8, 64);
    const b = try allocator.allocator.alloc(u8, 32);
    const c = try allocator.allocator.alloc(u8, 64);
    allocator.allocator.free(b);
    const d = try allocator.allocator.alloc(u8, 64);
    assert(d.ptr == b.ptr);

    try testAllocator(&allocator.allocator);
    try testAllocatorAligned(&allocator.allocator, 32);
    try testAllocatorLargeAlignment(&allocator.allocator);
    try testAllocatorAlignedShrink(&allocator.allocator);
}

// general purpose allocator tests, copied from std/heap.zig
fn testAllocator(allocator: *mem.Allocator) !void {
    var slice = try allocator.alloc(*i32, 100);
    testing.expect(slice.len == 100);
    for (slice) |*item, i| {
        item.* = try allocator.create(i32);
        item.*.* = @intCast(i32, i);
    }

    slice = try allocator.realloc(slice, 20000);
    testing.expect(slice.len == 20000);

    for (slice[0..100]) |item, i| {
        testing.expect(item.* == @intCast(i32, i));
        allocator.destroy(item);
    }

    slice = allocator.shrink(slice, 50);
    testing.expect(slice.len == 50);
    slice = allocator.shrink(slice, 25);
    testing.expect(slice.len == 25);
    slice = allocator.shrink(slice, 0);
    testing.expect(slice.len == 0);
    slice = try allocator.realloc(slice, 10);
    testing.expect(slice.len == 10);

    allocator.free(slice);
}

fn testAllocatorAligned(allocator: *mem.Allocator, comptime alignment: u29) !void {
    // initial
    var slice = try allocator.alignedAlloc(u8, alignment, 10);
    testing.expect(slice.len == 10);
    // grow
    slice = try allocator.realloc(slice, 100);
    testing.expect(slice.len == 100);
    // shrink
    slice = allocator.shrink(slice, 10);
    testing.expect(slice.len == 10);
    // go to zero
    slice = allocator.shrink(slice, 0);
    testing.expect(slice.len == 0);
    // realloc from zero
    slice = try allocator.realloc(slice, 100);
    testing.expect(slice.len == 100);
    // shrink with shrink
    slice = allocator.shrink(slice, 10);
    testing.expect(slice.len == 10);
    // shrink to zero
    slice = allocator.shrink(slice, 0);
    testing.expect(slice.len == 0);
}

fn testAllocatorLargeAlignment(allocator: *mem.Allocator) mem.Allocator.Error!void {
    //Maybe a platform's page_size is actually the same as or
    //  very near usize?
    if (mem.page_size << 2 > math.maxInt(usize)) return;

    const USizeShift = @IntType(false, math.log2(usize.bit_count));
    const large_align = u29(mem.page_size << 2);

    var align_mask: usize = undefined;
    _ = @shlWithOverflow(usize, ~usize(0), USizeShift(@ctz(u29, large_align)), &align_mask);

    var slice = try allocator.alignedAlloc(u8, large_align, 500);
    testing.expect(@ptrToInt(slice.ptr) & align_mask == @ptrToInt(slice.ptr));

    slice = allocator.shrink(slice, 100);
    testing.expect(@ptrToInt(slice.ptr) & align_mask == @ptrToInt(slice.ptr));

    slice = try allocator.realloc(slice, 5000);
    testing.expect(@ptrToInt(slice.ptr) & align_mask == @ptrToInt(slice.ptr));

    slice = allocator.shrink(slice, 10);
    testing.expect(@ptrToInt(slice.ptr) & align_mask == @ptrToInt(slice.ptr));

    slice = try allocator.realloc(slice, 20000);
    testing.expect(@ptrToInt(slice.ptr) & align_mask == @ptrToInt(slice.ptr));

    allocator.free(slice);
}

fn testAllocatorAlignedShrink(allocator: *mem.Allocator) mem.Allocator.Error!void {
    var debug_buffer: [1000]u8 = undefined;
    const debug_allocator = &std.heap.FixedBufferAllocator.init(&debug_buffer).allocator;

    const alloc_size = mem.page_size * 2 + 50;
    var slice = try allocator.alignedAlloc(u8, 16, alloc_size);
    defer allocator.free(slice);

    var stuff_to_free = std.ArrayList([]align(16) u8).init(debug_allocator);
    // On Windows, VirtualAlloc returns addresses aligned to a 64K boundary,
    // which is 16 pages, hence the 32. This test may require to increase
    // the size of the allocations feeding the `allocator` parameter if they
    // fail, because of this high over-alignment we want to have.
    while (@ptrToInt(slice.ptr) == mem.alignForward(@ptrToInt(slice.ptr), mem.page_size * 32)) {
        try stuff_to_free.append(slice);
        slice = try allocator.alignedAlloc(u8, 16, alloc_size);
    }
    while (stuff_to_free.popOrNull()) |item| {
        allocator.free(item);
    }
    slice[0] = 0x12;
    slice[60] = 0x34;

    // realloc to a smaller size but with a larger alignment
    slice = try allocator.alignedRealloc(slice, mem.page_size * 32, alloc_size / 2);
    testing.expect(slice[0] == 0x12);
    testing.expect(slice[60] == 0x34);
}
