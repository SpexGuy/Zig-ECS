const builtin = @import("builtin");
const AtomicOrder = builtin.AtomicOrder;
const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;
const SpinLock = std.SpinLock;

/// an InstantQueue is a threadsafe queue with a fixed-size buffer.
/// It is guaranteed never to sleep the thread.  It uses SpinLocks
/// to enforce consistency because I'm bad at lockless concurrency.
/// But it keeps a separate lock for enqueue and dequeue, so it can
/// have one producer and one consumer running at a time.
pub fn InstantQueue(comptime T: type, comptime MaxSize: u32) type {
    const N = MaxSize + 1;
    return struct {
        const Self = @This();

        // grumble grumble
        // we don't have control over struct layout in Zig
        // which means these two spin-locks will probably
        // end up on the same cache line, slowing down the
        // single-producer single-consumer case with false
        // sharing.  Because of this, spsc use cases should
        // prefer a more specialized queue implementation.

        headLock: SpinLock,
        tailLock: SpinLock,
        head: u32,
        tail: u32,
        buffer: [N]T,

        pub fn init() Self {
            return Self{
                .headLock = SpinLock.init(),
                .tailLock = SpinLock.init(),
                .head = 0,
                .tail = N - 1,
                .buffer = undefined,
            };
        }

        pub fn enqueue(self: *Self, value: T) error{QueueFull}!void {
            const lock = self.headLock.acquire();
            defer lock.release();
            const tail = @atomicLoad(u32, &self.tail, .SeqCst);
            var head = self.head;
            if (head == tail) return error.QueueFull;
            self.buffer[head] = value;
            head += 1;
            if (head == N) head = 0;
            _ = @atomicRmw(u32, &self.head, .Xchg, head, .SeqCst);
        }

        pub fn dequeue(self: *Self) error{QueueEmpty}!T {
            var value: T = undefined;
            {
                const lock = self.tailLock.acquire();
                defer lock.release();
                const head = @atomicLoad(u32, &self.head, .SeqCst);
                var tail = self.tail;
                tail += 1;
                if (tail == N) tail = 0;
                if (head == tail) return error.QueueEmpty;
                value = self.buffer[tail];
                _ = @atomicRmw(u32, &self.tail, .Xchg, tail, .SeqCst);
            }
            return value;
        }
    };
}

// -------------------------- Tests -----------------------------

test "std.atomic.Queue single-threaded" {
    var queue = InstantQueue(i32, 3).init();

    try queue.enqueue(0);
    try queue.enqueue(1);

    expect(0 == try queue.dequeue());

    try queue.enqueue(2);
    try queue.enqueue(3);

    if (queue.enqueue(4)) {
        expect(false);
    } else |err| {
        expect(err == error.QueueFull);
    }

    expect(1 == try queue.dequeue());
    expect(2 == try queue.dequeue());

    try queue.enqueue(4);

    expect(3 == try queue.dequeue());
    expect(4 == try queue.dequeue());

    if (queue.dequeue()) |_| {
        expect(false);
    } else |err| {
        expect(err == error.QueueEmpty);
    }
}

const Context = struct {
    allocator: *std.mem.Allocator,
    queue: *InstantQueue(i32, 64),
    put_sum: isize,
    get_sum: isize,
    get_count: usize,
    puts_done: u8, // TODO make this a bool
};

// TODO add lazy evaluated build options and then put puts_per_thread behind
// some option such as: "AggressiveMultithreadedFuzzTest". In the AppVeyor
// CI we would use a less aggressive setting since at 1 core, while we still
// want this test to pass, we need a smaller value since there is so much thrashing
// we would also use a less aggressive setting when running in valgrind
const puts_per_thread = 500;
const put_thread_count = 3;

test "std.atomic.Queue" {
    var plenty_of_memory = try std.heap.direct_allocator.alloc(u8, 300 * 1024);
    defer std.heap.direct_allocator.free(plenty_of_memory);

    var fixed_buffer_allocator = std.heap.ThreadSafeFixedBufferAllocator.init(plenty_of_memory);
    var a = &fixed_buffer_allocator.allocator;

    var queue = InstantQueue(i32, 64).init();
    var context = Context{
        .allocator = a,
        .queue = &queue,
        .put_sum = 0,
        .get_sum = 0,
        .puts_done = 0,
        .get_count = 0,
    };

    if (builtin.single_threaded) {
        expect(context.queue.isEmpty());
        {
            var i: usize = 0;
            while (i < put_thread_count) : (i += 1) {
                expect(startPuts(&context) == 0);
            }
        }
        expect(!context.queue.isEmpty());
        context.puts_done = 1;
        {
            var i: usize = 0;
            while (i < put_thread_count) : (i += 1) {
                expect(startGets(&context) == 0);
            }
        }
        expect(context.queue.isEmpty());
    } else {
        var putters: [put_thread_count]*std.Thread = undefined;
        for (putters) |*t| {
            t.* = try std.Thread.spawn(&context, startPuts);
        }
        var getters: [put_thread_count]*std.Thread = undefined;
        for (getters) |*t| {
            t.* = try std.Thread.spawn(&context, startGets);
        }

        for (putters) |t|
            t.wait();
        _ = @atomicRmw(u8, &context.puts_done, builtin.AtomicRmwOp.Xchg, 1, AtomicOrder.SeqCst);
        for (getters) |t|
            t.wait();
    }

    if (context.get_count != puts_per_thread * put_thread_count) {
        std.debug.panic(
            "failure\nget_count:{} != puts_per_thread:{} * put_thread_count:{}",
            context.get_count,
            u32(puts_per_thread),
            u32(put_thread_count),
        );
    }

    if (context.put_sum != context.get_sum) {
        std.debug.panic("failure\nput_sum:{} != get_sum:{}", context.put_sum, context.get_sum);
    }
}

fn startPuts(ctx: *Context) u8 {
    var put_count: usize = puts_per_thread;
    var r = std.rand.DefaultPrng.init(0xdeadbeef);
    while (put_count != 0) : (put_count -= 1) {
        std.time.sleep(1); // let the os scheduler be our fuzz
        const x = @bitCast(i32, r.random.scalar(u32));
        while (true) {
            if (ctx.queue.enqueue(x)) {
                _ = @atomicRmw(isize, &ctx.put_sum, builtin.AtomicRmwOp.Add, x, AtomicOrder.SeqCst);
                break;
            } else |err| {}
        }
    }
    return 0;
}

fn startGets(ctx: *Context) u8 {
    while (true) {
        const last = @atomicLoad(u8, &ctx.puts_done, builtin.AtomicOrder.SeqCst) == 1;

        while (ctx.queue.dequeue()) |data| {
            _ = @atomicRmw(isize, &ctx.get_sum, builtin.AtomicRmwOp.Add, data, builtin.AtomicOrder.SeqCst);
            _ = @atomicRmw(usize, &ctx.get_count, builtin.AtomicRmwOp.Add, 1, builtin.AtomicOrder.SeqCst);
        } else |err| {}

        if (last) return 0;
    }
}
