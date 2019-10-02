const std = @import("std");
const os = std.os;
const assert = std.debug.assert;
const warn = std.debug.warn;
const layout = @import("chunk_layout.zig");
const TypeLayout = layout.TypeLayout;
const layoutChunk = layout.layoutChunk;

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
            const layoutDesc = comptime layout.layoutStaticChunk(std.mem.page_size, 0, [_]TypeLayout{
                TypeLayout.init(Entity),
                TypeLayout.init(ArchMask),
                TypeLayout.init(u32),
            });
        };
    };
}

pub const Generation = packed struct {
    value: u8,
};

pub const Entity = packed struct {
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

    const ArchID = ZCS.ArchMask;
    const ChunkID = packed struct {
        value: u32,
    };

    const offsets = ZCS.EntityManager.layoutDesc.offsets;
    const numItems = ZCS.EntityManager.layoutDesc.numItems;
    warn("Laid out chunk, {} items, offsets:\n", numItems);
    warn("Entity  {}\n", offsets[0]);
    warn("ArchID  {}\n", offsets[1]);
    warn("ChunkID {}\n", offsets[2]);
    const end = offsets[2] + numItems * @sizeOf(ChunkID);
    const extra = std.mem.page_size - end;
    warn("Extra bytes: {}\n", extra);
}
