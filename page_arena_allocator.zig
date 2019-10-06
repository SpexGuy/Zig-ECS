const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const heap = std.heap;
const math = std.math;
const util = @import("util.zig");

const page_allocator = heap.direct_allocator;

/// This allocator
pub const PageArenaAllocator = struct {
    const Self = @This();

    const Header = struct {
        next: ?*@This(),
    };

    const DirectAlloc = struct {
        next: ?*@This(),
        mem: []u8,
        alignment: u29,
    };

    pub allocator: mem.Allocator,
    pageSize: u29,
    currentPage: ?*Header,
    directAllocs: ?*DirectAlloc,
    endIndex: usize,

    const BufNode = std.SinglyLinkedList([]u8).Node;

    pub fn init(pageSize: u32) Self {
        return Self{
            .allocator = mem.Allocator{
                .reallocFn = realloc,
                .shrinkFn = shrink,
            },
            .pageSize = @intCast(u29, pageSize),
            .currentPage = null,
            .directAllocs = null,
            .endIndex = pageSize, // this will cause a new page to be allocated
        };
    }

    pub fn deinit(self: *Self) void {
        // first free direct allocations
        var directIt = self.directAllocs;
        while (directIt) |allocation| {
            _ = page_allocator.shrinkFn(page_allocator, allocation.mem, allocation.alignment, 0, 0);
            directIt = allocation.next;
        }
        self.directAllocs = null;

        var pageIt = self.currentPage;
        while (pageIt) |page| {
            // this has to occur before the free because the free frees node
            const next = page.next;
            self.freePage(page);
            pageIt = next;
        }
        self.currentPage = null;
        self.endIndex = self.pageSize;
    }

    fn realloc(allocator: *mem.Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) ![]u8 {
        if (new_size <= old_mem.len and util.isAlignedPtr(old_mem.ptr, new_align)) {
            return old_mem[0..new_size];
        } else {
            const self = @fieldParentPtr(Self, "allocator", allocator);
            const result = try self.alloc(new_size, new_align);
            @memcpy(result.ptr, old_mem.ptr, math.min(old_mem.len, result.len));
            return result;
        }
    }

    fn shrink(allocator: *mem.Allocator, old_mem: []u8, old_align: u29, new_size: usize, new_align: u29) []u8 {
        return old_mem[0..new_size];
    }

    fn alloc(self: *Self, size: usize, alignment: u29) ![]u8 {
        if (self.shouldDirectAlloc(size, alignment)) {
            return try self.allocDirect(size, alignment);
        } else {
            return try self.allocOnPage(size, alignment);
        }
    }

    fn shouldDirectAlloc(self: Self, size: usize, alignment: u29) bool {
        if (util.alignUp(@sizeOf(Header), alignment) + size > self.pageSize) return true;
        const directWastedBytes = @sizeOf(DirectAlloc) + util.alignUp(size, self.pageSize) - size;
        const pageWastedBytes = util.alignUp(@sizeOf(Header), alignment) - @sizeOf(Header) + self.pageSize - self.endIndex;
        return directWastedBytes < pageWastedBytes;
    }

    fn allocDirect(self: *Self, size: usize, alignment: u29) ![]u8 {
        const sizeFullPages = util.alignUp(size, self.pageSize);

        const page = try page_allocator.reallocFn(page_allocator, util.emptySlice(u8), 0, sizeFullPages, alignment);
        errdefer self.freePage(@ptrCast(*Header, @alignCast(4096, page.ptr)));

        const metaMem = try self.allocOnPage(@sizeOf(DirectAlloc), @alignOf(DirectAlloc));
        const meta = @ptrCast(*DirectAlloc, @alignCast(@alignOf(DirectAlloc), metaMem.ptr));

        meta.* = DirectAlloc{
            .next = self.directAllocs,
            .mem = page,
            .alignment = alignment,
        };
        self.directAllocs = meta;

        return page[0..size];
    }

    fn allocOnPage(self: *Self, size: usize, alignment: u29) ![]u8 {
        var position = util.alignUp(self.endIndex, alignment);
        var end = position + size;
        if (end > self.pageSize) {
            try self.newPage();
            position = util.alignUp(self.endIndex, alignment);
            end = position + size;
            assert(end <= self.pageSize);
        }
        const base = util.adjustPtr(u8, self.currentPage.?, @intCast(isize, position));
        self.endIndex = end;
        return base[0..size];
    }

    fn newPage(self: *Self) !void {
        const page = try page_allocator.reallocFn(page_allocator, util.emptySlice(u8), 0, self.pageSize, self.pageSize);
        const header = @ptrCast(*Header, @alignCast(4096, page.ptr));
        header.* = Header{
            .next = self.currentPage,
        };
        self.currentPage = header;
        self.endIndex = @sizeOf(Header);
    }

    fn freePage(self: Self, page: *Header) void {
        const pageMem = @ptrCast([*]u8, page)[0..self.pageSize];
        _ = page_allocator.shrinkFn(page_allocator, pageMem, self.pageSize, 0, 0);
    }
};

test "page arena allocator" {
    var allocator = PageArenaAllocator.init(4096);
    try @import("test_allocator.zig").testAll(&allocator.allocator);
    allocator.deinit();
    try @import("test_allocator.zig").testAll(&allocator.allocator);
}
