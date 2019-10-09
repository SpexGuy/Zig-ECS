const std = @import("std");
const os = std.os;
const mem = std.mem;
const assert = std.debug.assert;
const warn = std.debug.warn;
const layout = @import("chunk_layout.zig");
const TypeLayout = layout.TypeLayout;
const layoutChunk = layout.layoutChunk;
const util = @import("util.zig");
const PageArenaAllocator = @import("page_arena_allocator.zig").PageArenaAllocator;
const BlockHeap = @import("block_heap.zig").BlockHeap;
const ArrayList = std.ArrayList;

const chunkSize = 64 * 1024;
const entityChunkSize = 64 * 1024;
const chunkChunkSize = mem.page_size;
const archChunkSize = mem.page_size;

var tempAllocator = PageArenaAllocator.init(64 * 1024);
var permAllocator = PageArenaAllocator.init(64 * 1024);
var heapAllocator = BlockHeap.init();

const stdTempAllocator = &tempAllocator.allocator;
const stdPermAllocator = &permAllocator.allocator;
const stdHeapAllocator = &heapAllocator.allocator;

var lowMemory = false;

/// Creates a ZCS type for the given set of components.
/// This file should be used via this syntax:
/// const ZCS = @import("zcs.zig").Schema([_]type{
///     // component types go here
/// });
pub fn Schema(comptime componentTypes: []const type) type {
    return struct {
        /// The type of archetype masks within this schema.  This is the
        /// smallest integer type made up of a power-of-two number of bytes
        /// that can fit a bit for each component in the componentTypes array.
        const ArchMask = GetArchetypeMaskType(componentTypes.len);
        const ArchID = GetArchetypeIndexType(componentTypes.len);

        /// Returns a mask with the component bits set for each component
        /// in the array.  Evaluates to a compile-time constant.  It is
        /// a compile error to pass any type to this function that is not
        /// in the componentTypes array.
        pub fn getArchMask(comptime types: []const type) ArchMask {
            comptime var mask: ArchMask = 0;
            inline for (types) |CompType| {
                mask |= comptime getComponentBit(CompType);
            }
            return mask;
        }

        /// Returns a mask with a single bit set to mark this component.
        /// Evaluates to a compile-time constant.  It is a compile error
        /// to pass a parameter to this function that is not in the
        /// componentTypes array.
        pub fn getComponentBit(comptime CompType: type) ArchMask {
            return 1 << comptime getComponentIndex(CompType);
        }

        // Make sure that there are no duplicates in the list of component types
        comptime {
            for (componentTypes) |CompType, i| {
                if (getComponentIndex(CompType) != i)
                    @compileError("List of component types cannot contain duplicates");
            }
        }

        /// Returns a unique identifier for the component type.
        /// Identifiers start at 0 and are dense.  They are equal
        /// to the index in the componentTypes array.  It is a compile
        /// error to pass a parameter to this function that is not in
        /// the componentTypes array.
        fn getComponentIndex(comptime CompType: type) u32 {
            for (componentTypes) |OtherType, i| {
                if (OtherType == CompType) return i;
            }
            @compileError("Not a component type");
        }

        pub const EntityManager = struct {
            const EntityData = union(enum) {
                Chunk: ChunkID,
                Gen: Generation,
            };
            const ChunkSchema = layout.SOASchema(util.EmptyStruct, EntityData);
            const Chunk = ChunkSchema.Chunk;
            const chunkLayout = comptime ChunkSchema.layout(entityChunkSize);
        };

        pub const ChunkManager = struct {
            const ChunkHeader = struct {
                next: *ChunkHeader,
            };
            const ChunkMetaData = union(enum) {
                ChunkData: *ChunkDataHeader,
                NextChunkInArchetype: ChunkID,
                Arch: ArchID,
            };
            const ChunkSchema = layout.SOASchema(ChunkHeader, ChunkMetaData);
            const Chunk = ChunkSchema.Chunk;
            const chunkLayout = comptime ChunkSchema.layout(chunkChunkSize);
        };

        pub const ArchetypeManager = struct {
            const Self = @This();

            const ArchetypeHeader = struct {
                next: ?*ArchetypeHeader,
            };
            const ArchetypeData = union(enum) {
                Components: []ComponentMeta,
                FirstChunk: ChunkID,
                Mask: ArchMask,
            };
            const ChunkSchema = layout.SOASchema(ArchetypeHeader, ArchetypeData);
            const Chunk = ChunkSchema.Chunk;
            const chunkLayout = comptime ChunkSchema.layout(archChunkSize);

            firstPage: ?*ArchetypeHeader = null,

            /// Finds all archetypes matching an include and exclude filter.
            /// The returned slice is valid until the temp allocator is cleared.
            pub fn findAllArchetypes(self: Self, include: ArchMask, exclude: ArchMask) []ArchetypeChunks {
                assert(include & exclude == 0);
                var archList = ArrayList(ArchetypeChunks).init(stdTempAllocator);
                const checkMask = include | exclude;
                var pageIt = self.firstPage;
                pageLoop: while (pageIt) |header| : (pageIt = header.next) {
                    const chunk = chunkLayout.getChunkFromHeader(header);
                    const components = chunkLayout.getValues(chunk, .Components);
                    const firstChunks = chunkLayout.getValues(chunk, .FirstChunk);
                    const masks = chunkLayout.getValues(chunk, .Mask);
                    for (masks) |mask, i| {
                        if (mask & checkMask == include) {
                            if (archList.addOne()) |pItem| {
                                pItem.* = ArchetypeChunks{
                                    .components = components[i],
                                    .firstChunk = firstChunks[i],
                                };
                            } else |err| {
                                lowMemory = true;
                                break :pageLoop;
                            }
                        }
                    }
                }
                //N.B. This looks like a leak but it's not because we're
                //using the temp allocator, where free() is a noop.
                return archList.toSlice();
            }
        };

        const ComponentMeta = struct {
            componentIndex: u32,
            chunkOffset: u32,
        };

        const ArchetypeChunks = struct {
            components: []ComponentMeta,
            firstChunk: ChunkID,
        };

        pub const ChunkDataHeader = struct {
            _notEmpty: u8 align(chunkSize),
        };
    };
}

pub const Generation = struct {
    value: u8,
};

pub const ChunkID = struct {
    value: u32,
};

pub const invalidChunkID = ChunkID{
    .value = 0xFFFFFFFF,
};

pub const Entity = struct {
    /// MSB 8 bytes are generation, rest is index
    gen_index: u32,
};

fn GetArchetypeMaskType(comptime numComponentTypes: u32) type {
    return switch (numComponentTypes) {
        0 => @compileError("Cannot create an ECS with 0 component types"),
        1...8 => u8,
        9...16 => u16,
        17...32 => u32,
        33...64 => u64,
        65...128 => u128,
        else => @compileError("Cannot create an ECS with more than 128 component types"),
    };
}

fn GetArchetypeIndexType(comptime numComponentTypes: u32) type {
    return switch (numComponentTypes) {
        0 => @compileError("Cannot create an ECS with 0 component types"),
        1...8 => u8,
        9...16 => u16,
        else => u32, // can't have more than 4 billion active archetypes
    };
}

test "Masks" {
    const vec3 = struct {
        x: f32,
        y: f32,
        z: f32,
    };
    const Position = struct {
        pos: vec3,
    };
    const Velocity = struct {
        vel: vec3,
    };
    const Acceleration = struct {
        acc: vec3,
    };
    const GravityTag = struct {};
    const GravityTag2 = GravityTag;
    const DampenTag = struct {};

    const ZCS = Schema([_]type{ Position, Velocity, Acceleration, GravityTag, DampenTag });

    assert(ZCS.ArchMask == u8);
    assert(ZCS.getComponentBit(Position) == 1);
    assert(ZCS.getComponentBit(Velocity) == 2);
    assert(ZCS.getComponentBit(Acceleration) == 4);
    assert(ZCS.getComponentBit(GravityTag) == 8);
    assert(ZCS.getComponentBit(GravityTag2) == 8);
    assert(ZCS.getComponentBit(DampenTag) == 16);
    assert(ZCS.getArchMask([_]type{ Position, Velocity, GravityTag }) == 11);

    const offsets = ZCS.EntityManager.chunkLayout.layout.offsets;
    const numItems = ZCS.EntityManager.chunkLayout.layout.numItems;
    warn("Laid out chunk, {} items, offsets:\n", numItems);
    warn("Entity  {}\n", offsets[0]);
    warn("ArchID  {}\n", offsets[1]);
    const end = offsets[1] + numItems * @sizeOf(ZCS.EntityManager.ChunkSchema.ValTypeIndex(1));
    const extra = entityChunkSize - end;
    warn("Extra bytes: {}\n", extra);

    var archMan = ZCS.ArchetypeManager{};
    _ = archMan.findAllArchetypes(0, 0);
}
