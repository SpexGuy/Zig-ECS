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

pub const RefrigeratorAllocator = struct {
    const Self = @This();

    blockSize: u32,
    dataPageSlots: u32,
    firstHeader: ?*IndexPageHeader = null,

    pub fn init(size: u32) RefrigeratorAllocator {
        assert(util.isPowerOfTwo(size));
        return RefrigeratorAllocator{
            .blockSize = size,
            .dataPageSlots = page_size / size,
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
                freeSlotsArray[i] -= 1;
                return self.allocFromDataPage(dataPage);
            }
        }
        // all used data pages are full, can we make a new one?
        const numSlots = IndexPage.layout.numItems;
        if (inUse < numSlots) {
            const newPage = try self.newDataPage(); // OutOfMemory
            // link the new page
            const dataPtrArray = page.getValues(.Data);
            dataPtrArray[inUse] = newPage;
            freeSlotsArray[inUse] = self.dataPageSlots - 1; // -1 because we are about to allocate on it
            page.header.inUse += 1;
            // alloc on the new page
            return self.allocFromDataPage(newPage);
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

    fn allocFromDataPage(self: Self, page: *DataPage) []u8 {
        var data: []u8 = [_]u8{};
        return data;
    }

    fn newIndexPage(self: Self) !*IndexPage {
        const newPage = try std.heap.direct_allocator.create(IndexPage);
        newPage.header = IndexPageHeader{};
        return newPage;
    }

    fn newDataPage(self: Self) !*DataPage {
        return error.OutOfMemory;
    }

    const DataPage = struct {
        data: u32,
    };
};

test "fridge alloc" {
    var allocator = RefrigeratorAllocator.init(64);
    _ = try allocator.alloc();
}
