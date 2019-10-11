pub fn TypeIndex(comptime componentTypes: []const type) type {
    return struct {
        /// The type of archetype masks within this schema.  This is the
        /// smallest integer type made up of a power-of-two number of bytes
        /// that can fit a bit for each component in the componentTypes array.
        pub const ArchMask = GetArchetypeMaskType(componentTypes.len);
        pub const ArchID = GetArchetypeIndexType(componentTypes.len);

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
        pub fn getComponentIndex(comptime CompType: type) u32 {
            for (componentTypes) |OtherType, i| {
                if (OtherType == CompType) return i;
            }
            @compileError("Not a component type");
        }
    };
}

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
