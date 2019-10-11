const std = @import("std");
const os = std.os;
const mem = std.mem;
const assert = std.debug.assert;
const warn = std.debug.warn;
const ArrayList = std.ArrayList;

const layout = @import("chunk_layout.zig");
const TypeLayout = layout.TypeLayout;
const layoutChunk = layout.layoutChunk;
const util = @import("util.zig");
const PageArenaAllocator = @import("page_arena_allocator.zig").PageArenaAllocator;
const BlockHeap = @import("block_heap.zig").BlockHeap;
const type_meta = @import("type_meta.zig");
const pages = @import("pages.zig");

const chunkSize = 16 * 1024;
const entityChunkSize = 64 * 1024;
const dataChunkSize = 8 * 1024;
const archChunkSize = 8 * 1024;

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
    const TypeIndex = type_meta.TypeIndex(componentTypes);
    const ArchMask = TypeIndex.ArchMask;
    const ArchID = TypeIndex.ArchID;

    const ComponentMeta = struct {
        componentIndex: u32,
        chunkOffset: u32,
    };

    const ChunkDataHeader = struct {
        data: [chunkSize]u8 align(mem.page_size),
    };

    const EntityManager = struct {
        const Self = @This();
        const EntityData = union(enum) {
            Chunk: ChunkID,
            Index: u16,
            Gen: Generation,
        };
        const ChunkSchema = layout.SOASchema(util.EmptyStruct, EntityData);
        const Chunk = ChunkSchema.Chunk;
        const chunkLayout = comptime ChunkSchema.layout(entityChunkSize);
        const ChunkList = ArrayList(*Chunk);
        const Item = struct {
            chunk: *Chunk,
            index: u32,

            fn getValue(self: Item, comptime value: ChunkSchema.Values) ChunkSchema.ValType(value) {
                return chunkLayout.getValues(self.chunk, value)[self.index];
            }
        };

        chunks: ChunkList,

        fn init() Self {
            return Self{
                .chunks = ChunkList.init(stdHeapAllocator),
            };
        }

        fn resolveItem(index: u32) error{InvalidID}!Item {
            const chunkID = index / chunkLayout.numItems;
            const indexInChunk = index % chunkLayout.numItems;
            if (chunkID >= self.chunks.count()) return error.InvalidID;
            return Item{
                .chunk = self.chunks.at(chunkID),
                .index = indexInChunk,
            };
        }
    };

    const DataManager = struct {
        const Self = @This();
        const ChunkMetaData = union(enum) {
            ChunkData: *ChunkDataHeader,
            Arch: ArchID,
            Mask: ArchMask,
            Count: u16,
        };
        const ChunkSchema = layout.SOASchema(util.EmptyStruct, ChunkMetaData);
        const Chunk = ChunkSchema.Chunk;
        const chunkLayout = comptime ChunkSchema.layout(dataChunkSize);
        const ChunkList = ArrayList(*Chunk);
        const Item = struct {
            chunk: *Chunk,
            index: u32,

            fn getValue(self: Item, comptime value: ChunkSchema.Values) ChunkSchema.ValType(value) {
                return chunkLayout.getValues(self.chunk, value)[self.index];
            }
        };

        chunks: ChunkList,

        fn init() Self {
            return Self{
                .chunks = ChunkList.init(stdHeapAllocator),
            };
        }

        fn resolveItem(index: u32) error{InvalidID}!Item {
            const chunkID = index / chunkLayout.numItems;
            const indexInChunk = index % chunkLayout.numItems;
            if (chunkID >= self.chunks.count()) return error.InvalidID;
            return Item{
                .chunk = self.chunks.at(chunkID),
                .index = indexInChunk,
            };
        }
    };

    const ArchetypeManager = struct {
        const Self = @This();
        const ArchetypeData = union(enum) {
            Components: []ComponentMeta,
            Mask: ArchMask,
            ItemsPerChunk: u16,
        };
        const ChunkSchema = layout.SOASchema(util.EmptyStruct, ArchetypeData);
        const Chunk = ChunkSchema.Chunk;
        const chunkLayout = comptime ChunkSchema.layout(archChunkSize);
        const ChunkList = ArrayList(*Chunk);
        const Item = struct {
            chunk: *Chunk,
            index: u32,

            fn getValue(self: Item, comptime value: ChunkSchema.Values) ChunkSchema.ValType(value) {
                return chunkLayout.getValues(self.chunk, value)[self.index];
            }
        };

        chunks: ChunkList,

        fn init() Self {
            return Self{
                .chunks = ChunkList.init(stdHeapAllocator),
            };
        }

        fn resolveItem(index: u32) error{InvalidID}!Item {
            const chunkID = index / chunkLayout.numItems;
            const indexInChunk = index % chunkLayout.numItems;
            if (chunkID >= self.chunks.count()) return error.InvalidID;
            return Item{
                .chunk = self.chunks.at(chunkID),
                .index = indexInChunk,
            };
        }
    };

    return ZCS(TypeIndex, EntityManager, ArchetypeManager, DataManager);
}

fn ZCS(
    comptime _TypeIndex: type,
    comptime _EntityManager: type,
    comptime _ArchetypeManager: type,
    comptime _DataManager: type,
) type {
    return struct {
        const Self = @This();

        pub const TypeIndex = _TypeIndex;
        pub const ArchMask = TypeIndex.ArchMask;
        pub const ArchID = TypeIndex.ArchID;

        pub const EntityManager = _EntityManager;
        pub const ArchetypeManager = _ArchetypeManager;
        pub const DataManager = _DataManager;

        pub const ArchetypeChunk = struct {
            arch: ArchetypeManager.Item,
            data: DataManager.Item,

            pub fn getEntities(self: ArchetypeChunk) []Entity {
                const dataChunk = self.data.getValue(.ChunkData);
                const validNum = self.data.getValue(.Count);
                return util.typedSlice(Entity, dataChunk, 0, validNum);
            }

            pub fn hasComponent(self: ArchetypeChunk, comptime T: type) bool {
                const compIndex = comptime TypeIndex.getComponentIndex(T);
                const components = self.arch.getValue(.Components);
                for (components) |component| {
                    if (component.componentIndex == compIndex)
                        return true;
                }
                return false;
            }

            pub fn getComponents(self: ArchetypeChunk, comptime T: type) error{MissingComponent}![]T {
                const compIndex = comptime TypeIndex.getComponentIndex(T);
                const components = self.arch.getValue(.Components);
                const offset = for (components) |component| {
                    if (component.componentIndex == compIndex)
                        break component.chunkOffset;
                } else {
                    return error.MissingComponent;
                };

                const dataChunk = self.data.getValue(.ChunkData);
                const validNum = self.data.getValue(.Count);
                return util.typedSlice(T, dataChunk, 0, validNum);
            }
        };

        entityManager: _EntityManager,
        archetypeManager: _ArchetypeManager,
        dataManager: _DataManager,

        pub fn init() Self {
            return Self{
                .entityManager = _EntityManager.init(),
                .archetypeManager = _ArchetypeManager.init(),
                .dataManager = _DataManager.init(),
            };
        }
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

    const ECS = Schema([_]type{ Position, Velocity, Acceleration, GravityTag, DampenTag });
    const TypeIndex = ECS.TypeIndex;

    assert(ECS.ArchMask == u8);
    assert(TypeIndex.getComponentBit(Position) == 1);
    assert(TypeIndex.getComponentBit(Velocity) == 2);
    assert(TypeIndex.getComponentBit(Acceleration) == 4);
    assert(TypeIndex.getComponentBit(GravityTag) == 8);
    assert(TypeIndex.getComponentBit(GravityTag2) == 8);
    assert(TypeIndex.getComponentBit(DampenTag) == 16);
    assert(TypeIndex.getArchMask([_]type{ Position, Velocity, GravityTag }) == 11);

    warn("\nLaid out chunks:\n");
    warn("Entity {}\n", ECS.EntityManager.chunkLayout.layout.numItems);
    warn("Arch    {}\n", ECS.ArchetypeManager.chunkLayout.layout.numItems);
    warn("Data    {}\n", ECS.DataManager.chunkLayout.layout.numItems);

    const ecs = ECS.init();
    const AC = ECS.ArchetypeChunk;
    const ac: AC = undefined;
    //_ = ac.getEntities();
    //_ = try ac.getComponents(Velocity);
    //_ = ac.hasComponent(GravityTag);
    //_ = ecs.archetypeManager.findAllArchetypes(0, 0);
}
