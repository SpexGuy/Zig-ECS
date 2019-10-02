const std = @import("std");
const assert = std.debug.assert;
const warn = std.debug.warn;
const z = @import("zcs.zig");

test "first_test" {
    z.doStuff();
}
