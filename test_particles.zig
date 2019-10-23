const std = @import("std");

const Vec = @import("vec.zig");
const Vec3 = Vec.Vec3;

const Position = struct {
    value: Vec3,
};

const Rotation = struct {
    theta: f32,
};

const Velocity = struct {
    value: Vec3,
};

const Brownian = struct {
    scale: f32,
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

const Speed = struct {
    value: f32,
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
    Brownian,
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

    const clearJob = world.forEntities(resetVelocity);
    const lifetime = world.forEntities(tickLifetime);
    const position = world.forEntities(updatePosition);

    defer world.shutdown();

    // TODO entity tests go here
}

var TimeDelta: f32 = 0.016666;

fn resetVelocity(entity: struct {
    vel: *Velocity,
}) void {
    entity.vel.* = Velocity{
        .value = Vec3.Zero,
    };
}

fn tickLifetime(entity: struct {
    life: *Lifetime,
}) void {
    entity.life.timeLeft -= TimeDelta;
}

fn updatePosition(entity: struct {
    vel: *const Velocity,
    pos: *Position,
}) void {
    entity.pos.value = entity.pos.value.add(entity.vel.value.scale(TimeDelta));
}
