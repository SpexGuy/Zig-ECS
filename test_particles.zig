const std = @import("std");

const Vec3 = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

const Position = struct {
    value: Vec3,
};

const Rotation = struct {
    theta: f32,
};

const Velocity = struct {
    value: Vec3,
};

const Acceleration = struct {
    value: Vec3,
};

const Sprite = struct {
    imageID: u32,
};

const Scale = struct {
    scale: f32,
};

const Color = struct {
    value: Vec3,
};

const Alpha = struct {
    value: f32,
};

const Size = struct {
    width: f32,
    height: f32,
};

const Gravity = struct {
    force: f32,
};

const Wind = struct {
    force: f32,
};

const Lifetime = struct {
    timeLeft: f32,
};

const Schema = @import("zcs.zig").Schema([_]type{
    Position,
    Velocity,
    Acceleration,
    Sprite,
    Scale,
    Color,
    Alpha,
    Size,
    Gravity,
    Wind,
    Lifetime,
});

test "particles" {
    const numCores = std.Thread.cpuCount() catch 4;
    var world = Schema.init();
    try world.startJobSystem(@intCast(u32, numCores - 1));
    defer world.shutdown();

    // TODO entity tests go here
}
