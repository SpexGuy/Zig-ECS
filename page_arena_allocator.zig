const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const math = std.math;
const util = @import("util.zig");
const pages = @import("pages.zig");

/// This allocator
pub const PageArenaAllocator = struct {
    const Self = @This();

    const Header = struct {
        next: ?*@This(),
    };

    const DirectAlloc = struct {
        next: ?*@This(),
        mem: []u8,
    };

    pub allocator: mem.Allocator,
    pageSize: u29,
    currentPage: ?*Header,
    directAllocs: ?*DirectAlloc,
    endIndex: usize,

    pub fn init(pageSize: u32) Self {
        assert(util.isPowerOfTwo(pageSize));
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
            pages.release(allocation.mem);
            directIt = allocation.next;
        }
        self.directAllocs = null;

        var pageIt = self.currentPage;
        while (pageIt) |pageHead| {
            // this has to occur before the free because the free frees node
            const next = pageHead.next;
            pages.releaseAs(pageHead, self.pageSize);
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
        assert(new_size <= old_mem.len);
        assert(util.isAlignedPtr(old_mem.ptr, new_align));
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
        const pageAlignment: u29 = math.max(mem.page_size, alignment);

        const pageMem = try pages.obtainAligned(sizeFullPages, pageAlignment);
        errdefer pages.release(pageMem);

        const metaMem = try self.allocOnPage(@sizeOf(DirectAlloc), @alignOf(DirectAlloc));
        const meta = @ptrCast(*DirectAlloc, @alignCast(@alignOf(DirectAlloc), metaMem.ptr));

        meta.* = DirectAlloc{
            .next = self.directAllocs,
            .mem = pageMem,
        };
        self.directAllocs = meta;

        return pageMem[0..size];
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
        const header = try pages.obtainAs(Header, self.pageSize);
        header.* = Header{
            .next = self.currentPage,
        };
        self.currentPage = header;
        self.endIndex = @sizeOf(Header);
    }
};

test "pages arena allocator" {
    var allocator = PageArenaAllocator.init(4096);
    try @import("test_allocator.zig").testAll(&allocator.allocator);
    allocator.deinit();
    try @import("test_allocator.zig").testAll(&allocator.allocator);
}
