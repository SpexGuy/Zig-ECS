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
const jobs = @import("job_system.zig");

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

        fn resolveItem(self: Self, index: u32) error{InvalidID}!Item {
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

        fn resolveItem(self: Self, index: u32) error{InvalidID}!Item {
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

        fn resolveItem(self: Self, index: u32) error{InvalidID}!Item {
            const chunkID = index / chunkLayout.layout.numItems;
            const indexInChunk = index % chunkLayout.layout.numItems;
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

        pub const JobSystem = jobs.JobSystem;
        pub const JobID = jobs.JobID;
        pub const JobInterface = jobs.JobInterface;

        pub const ArchetypeChunk = struct {
            arch: ArchetypeManager.Item,
            data: DataManager.Item,

            pub fn getCount(self: ArchetypeChunk) u32 {
                return self.data.getValue(.Count);
            }

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
        jobSystem: JobSystem,

        pub fn init() Self {
            var self = Self{
                .entityManager = _EntityManager.init(),
                .archetypeManager = _ArchetypeManager.init(),
                .dataManager = _DataManager.init(),
                .jobSystem = JobSystem.init(stdHeapAllocator),
            };
            return self;
        }

        pub fn startJobSystem(self: *Self, numThreads: u32) !void {
            try self.jobSystem.startup(numThreads);
        }

        pub fn shutdown(self: *Self) void {
            warn("shutting down ZCS\n");
            self.jobSystem.shutdown();
        }

        pub fn forEntities(self: *Self, comptime func: var) JobID {
            return self.forEntitiesExcludeWithDeps(0, func, util.emptySlice(JobID));
        }

        pub fn forEntitiesExclude(self: *Self, excludeMask: ArchMask, comptime func: var) JobID {
            return self.forEntitiesExcludeWithDeps(excludeMask, func, util.emptySlice(JobID));
        }

        pub fn forEntitiesWithDep(self: *Self, comptime func: var, dep: JobID) JobID {
            return self.forEntitiesExcludeWithDeps(0, func, [_]JobID{dep});
        }

        pub fn forEntitiesWithDeps(self: *Self, comptime func: var, deps: []const JobID) JobID {
            return self.forEntitiesExcludeWithDeps(0, func, deps);
        }

        pub fn forEntitiesExcludeWithDep(self: *Self, excludeMask: ArchMask, comptime func: var, dep: JobID) JobID {
            return self.forEntitiesExcludeWithDeps(excludeMask, func, [_]JobID{dep});
        }

        pub fn forEntitiesExcludeWithDeps(self: *Self, excludeMask: ArchMask, comptime func: var, deps: []const JobID) JobID {
            const FuncType = @typeOf(func);

            // Get the type of the second argument to func
            const ComponentStruct = switch (@typeInfo(FuncType)) {
                .Fn, .BoundFn => |funcInfo| Blk: {
                    if (funcInfo.return_type.? != void) @compileError("parameter func must not return a value");
                    if (funcInfo.args.len != 1) @compileError("parameter func must take one argument");
                    break :Blk funcInfo.args[0].arg_type.?;
                },
                else => @compileError("parameter func must be a function"),
            };

            // This gives a better error message than letting it get validated later
            const componentInfo = switch (@typeInfo(ComponentStruct)) {
                .Struct => |structInfo| structInfo,
                else => @compileError("parameter to func must be a struct of components"),
            };

            const Codegen = struct {
                fn dataAdapter(_: util.EmptyStruct, data: ComponentStruct) void {
                    @inlineCall(func, data);
                }
            };

            return self.forEntitiesWithDataExcludeWithDeps(excludeMask, util.EmptyStruct{}, Codegen.dataAdapter, deps);
        }

        pub fn forEntitiesWithData(self: *Self, data: var, comptime func: var) JobID {
            return self.forEntitiesWithDataExcludeWithDeps(0, data, func, util.emptySlice(JobID));
        }

        pub fn forEntitiesWithDataExclude(self: *Self, excludeMask: ArchMask, data: var, comptime func: var) JobID {
            return self.forEntitiesWithDataExcludeWithDeps(excludeMask, data, func, util.emptySlice(JobID));
        }

        pub fn forEntitiesWithDataWithDep(self: *Self, data: var, comptime func: var, dep: JobID) JobID {
            return self.forEntitiesWithDataExcludeWithDeps(0, data, func, [_]JobID{dep});
        }

        pub fn forEntitiesWithDataWithDeps(self: *Self, data: var, comptime func: var, deps: []const JobID) JobID {
            return self.forEntitiesWithDataExcludeWithDeps(0, data, func, deps);
        }

        pub fn forEntitiesWithDataExcludeWithDep(self: *Self, excludeMask: ArchMask, data: var, comptime func: var, dep: JobID) JobID {
            return self.forEntitiesWithDataExcludeWithDeps(excludeMask, data, func, [_]JobID{dep});
        }

        pub fn forEntitiesWithDataExcludeWithDeps(self: *Self, excludeMask: ArchMask, data: var, comptime func: var, deps: []const JobID) JobID {
            const ExtraData = @typeOf(data);
            const FuncType = @typeOf(func);

            // Get the type of the second argument to func
            const ComponentStruct = switch (@typeInfo(FuncType)) {
                .Fn, .BoundFn => |funcInfo| Blk: {
                    if (funcInfo.return_type.? != void) @compileError("parameter func must not return a value");
                    if (funcInfo.args.len != 2) @compileError("parameter func must take two arguments");
                    if (funcInfo.args[0].arg_type.? != ExtraData) @compileError("parameter func must take data as its first argument");
                    break :Blk funcInfo.args[1].arg_type.?;
                },
                else => @compileError("parameter func must be a function"),
            };

            // Get the struct info for that argument
            const componentInfo = switch (@typeInfo(ComponentStruct)) {
                .Struct => |structInfo| structInfo,
                else => @compileError("second argument to func must be a struct of components"),
            };

            // Get the mask for the set of needed components
            comptime var includeMask: ArchMask = 0;
            inline for (componentInfo.fields) |field| {
                includeMask |= comptime TypeIndex.getComponentBit(field.field_type.Child);
            }

            assert(includeMask & excludeMask == 0);

            // Generate parameter data layouts for the job system
            const SpawnQueryData = struct {
                self: *Self,
                excludeMask: ArchMask,
                data: ExtraData,
            };
            const QueryData = struct {
                self: *Self,
                chunk: *DataManager.Chunk,
                excludeMask: ArchMask,
                data: ExtraData,
            };
            const ChunkData = struct {
                chunk: ArchetypeChunk,
                data: ExtraData,
            };

            // Generate code for the job functions
            const Adapter = struct {
                // Root job: for each chunk of chunks, run queryJob
                fn spawnQueryJobs(job: JobInterface, jobData: SpawnQueryData) void {
                    for (jobData.self.dataManager.chunks.toSlice()) |chunk| {
                        const subData = QueryData{
                            .self = jobData.self,
                            .chunk = chunk,
                            .excludeMask = jobData.excludeMask,
                            .data = jobData.data,
                        };
                        _ = job.addSubJob(subData, queryJob);
                    }
                }
                // for each chunk, if its archetype matches our requirements, run rawChunkJob
                fn queryJob(job: JobInterface, jobData: QueryData) void {
                    const archIDs = DataManager.chunkLayout.getValues(jobData.chunk, .Arch);
                    const masks = DataManager.chunkLayout.getValues(jobData.chunk, .Mask);
                    const careMask = includeMask | jobData.excludeMask;
                    for (masks) |mask, i| {
                        if (mask & careMask == includeMask) {
                            const subData = ChunkData{
                                .chunk = ArchetypeChunk{
                                    .arch = jobData.self.archetypeManager.resolveItem(archIDs[i]) catch unreachable,
                                    .data = DataManager.Item{
                                        .chunk = jobData.chunk,
                                        .index = @intCast(u32, i),
                                    },
                                },
                                .data = jobData.data,
                            };
                            _ = job.addSubJob(subData, rawChunkJob);
                        }
                    }
                }
                // for each item in the chunk, run the job function
                fn rawChunkJob(job: JobInterface, jobData: ChunkData) void {
                    // get the data pointers for the chunks
                    var componentPtrs: [componentInfo.fields.len][*]u8 = undefined;
                    inline for (componentInfo.fields) |field, i| {
                        const slice = jobData.chunk.getComponents(field.field_type.Child) catch unreachable;
                        componentPtrs[i] = @ptrCast([*]u8, slice.ptr);
                    }

                    const numInChunk = jobData.chunk.getCount();

                    var chunkIndex: u32 = 0;
                    while (chunkIndex < numInChunk) : (chunkIndex += 1) {
                        var components: ComponentStruct = undefined;
                        inline for (componentInfo.fields) |field, i| {
                            const typedPtr = @ptrCast([*]field.field_type.Child, @alignCast(@alignOf(field.field_type.Child), componentPtrs[i]));
                            @field(components, field.name) = &typedPtr[i];
                        }
                        @inlineCall(func, jobData.data, components);
                    }
                }
            };

            // Schedule the job
            const jobData = SpawnQueryData{
                .self = self,
                .excludeMask = excludeMask,
                .data = data,
            };

            return self.jobSystem.scheduleWithDeps(jobData, Adapter.spawnQueryJobs, deps);
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

    const Jobs = struct {
        fn resetAcc(entity: struct {
            vel: *Velocity,
        }) void {
            entity.vel.* = Velocity{ .vel = vec3{ .x = 0, .y = 0, .z = 0 } };
        }
        fn accVel(dt: f32, entity: struct {
            acc: *const Acceleration,
            vel: *Velocity,
        }) void {
            entity.vel.vel.x += entity.acc.acc.x * dt;
            entity.vel.vel.y += entity.acc.acc.y * dt;
            entity.vel.vel.z += entity.acc.acc.z * dt;
        }
    };

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

    var ecs = ECS.init();
    try ecs.startJobSystem(0);
    const accVelJob = ecs.forEntitiesWithData(f32(0.016666), Jobs.accVel);
    _ = ecs.forEntitiesWithDep(Jobs.resetAcc, accVelJob);
    ecs.shutdown();

    const AC = ECS.ArchetypeChunk;
    const ac: AC = undefined;
    //_ = ac.getEntities();
    //_ = try ac.getComponents(Velocity);
    //_ = ac.hasComponent(GravityTag);
    //_ = ecs.archetypeManager.findAllArchetypes(0, 0);
}
