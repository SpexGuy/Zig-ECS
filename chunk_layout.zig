const std = @import("std");
const mem = std.mem;
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

/// Creates a data type which spans an entire aligned chunk of memory.
/// The type has a header and a series of spans of SOA data.
/// Consider this example:
///
/// const Header = struct { value: u8 };
/// const Values = union(enum) { Offset: u32, Ptr: *u32 };
/// const Example = StaticChunk(Header, Values, std.mem.page_size);
/// const instance = @ptrCast(*Example, try allocPage())
///
/// the Example type is 4096 bytes long and has an alignment of 4096.
/// Each instance is laid out as follows:
/// [u8|alignPad|u32|u32|...|u32|alignPad|u32*|u32*|...|u32*|alignPad]
///  ^ Header    ^^^ Offsets ^^^          ^^^^^^ Ptrs ^^^^^^
/// the alignPad regions may be empty if no alignment or padding is necessary.
/// To access the data arrays, use instance.getValues(.Offset) or instance.getValues(.Ptr)
/// To access the header, use instance.header.
/// To get the chunk from a pointer to the header, use instance = Example.getFromHeader(pHeader);
///
pub fn StaticChunk(comptime InHeader: type, comptime InValueUnion: type, comptime inChunkSize: u32) type {
    const inValueTypes = util.extractTypesFromUnion(InValueUnion);

    comptime var layouts: [inValueTypes.len]TypeLayout = undefined;
    inline for (inValueTypes) |ValType, i| {
        layouts[i] = TypeLayout.init(ValType);
    }

    const staticLayout = layoutStaticChunk(inChunkSize, @sizeOf(InHeader), layouts);

    assert(util.isPowerOfTwo(inChunkSize));
    assert(inChunkSize > @sizeOf(InHeader));

    // Zig doesn't allow pointers to structs of zero size, so we need to make sure
    // that the Chunk type has nonzero size.  In the case of a zero-sized header, we will
    // use u8 as the header type and it will overlap with the data.
    const ActualHeaderType = if (@sizeOf(InHeader) == 0) u8 else InHeader;

    return struct {
        // -------------- types --------------
        /// Type: the type of this anonymous struct
        const Self = @This();

        /// Type: the type of the block header.
        pub const Header = InHeader;

        /// Type: enum containing values for each data array.
        pub const Values = @TagType(InValueUnion);

        /// Type: returns the type of the component at the given index
        pub fn ValType(comptime value: Values) type {
            return ValTypeIndex(@enumToInt(value));
        }

        fn ValTypeIndex(comptime index: u32) type {
            if (index > inValueTypes.len)
                @compileError("Invalid data type index");
            return inValueTypes[index];
        }

        // -------------- constant values --------------
        pub const chunkSize = inChunkSize;
        pub const valueLayouts = layouts;
        pub const layout = staticLayout;

        // -------------- memory pattern --------------

        /// If the passed header was of zero size, this is u8 and may overlap data.
        header: ActualHeaderType align(inChunkSize),

        // -------------- functions --------------

        /// Given a pointer to somewhere within the data section of a chunk,
        /// this function returns a pointer to the parent chunk, from which
        /// the header or other data can be retrieved.
        pub fn getFromPointerInBlock(ptr: var) *Self {
            const address = @ptrToInt(ptr);
            const baseAddress = util.alignDown(address, chunkSize);
            return @intToPtr(*Self, baseAddress);
        }

        /// Get the slice of values for the given value type
        pub fn getValues(self: *Self, comptime value: Values) []ValType(value) {
            return getValuesIndex(self, @enumToInt(value));
        }

        /// Get the slice of values for the given value index
        fn getValuesIndex(self: *Self, comptime index: u32) []ValTypeIndex(index) {
            const T = ValTypeIndex(index);
            const valuesBase = util.adjustPtr(T, self, layout.offsets[index]);
            return valuesBase[0..layout.numItems];
        }

        /// Get the chunk object from a pointer to the header
        pub fn getFromHeader(ptr: *Header) *Self {
            return @fieldParentPtr(Self, "header", ptr);
        }

        // -------------- consistency --------------
        comptime {
            assert(@sizeOf(Self) == inChunkSize);
            assert(@alignOf(Self) == inChunkSize);
            // @todo: figure out how to assert at compile time that the offset of header is 0
        }
    };
}

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
        pos = @intCast(u32, util.alignUp(pos, info.alignment));
        outOffsets[i] = pos;
        pos += info.size * numItems;
    }
    return pos;
}

test "static chunk layout" {
    const Header = struct {
        next: ?*@This(),
    };
    const chunkSize = 4096;
    const LinkedChunk = StaticChunk(Header, union(enum) {
        First: u32,
        Second: u64,
        Third: *u32,
    }, chunkSize);
    const chunk = try std.heap.direct_allocator.create(LinkedChunk);
    chunk.header.next = &chunk.header;

    const longs = chunk.getValues(.First);
    const offset = util.ptrDiff(chunk, longs.ptr);
    //std.debug.warn("offset {} is {}, count is {}\n", @typeName(Type), diff, longs.len);
    assert(@intCast(u32, offset) == LinkedChunk.layout.offsets[0]);

    assert(LinkedChunk.getFromHeader(&chunk.header) == chunk);
    assert(util.ptrDiff(&chunk.header, chunk) == 0);
}
