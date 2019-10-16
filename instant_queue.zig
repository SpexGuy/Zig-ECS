const builtin = @import("builtin");
const AtomicOrder = builtin.AtomicOrder;
const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;
const SpinLock = std.SpinLock;

/// an InstantQueue is a threadsafe queue with a fixed-size buffer.
/// It is guaranteed never to sleep the thread.
pub fn InstantQueue(comptime T: type, comptime MaxSize: u32) type {
    const N = MaxSize + 1;
    return struct {
        const Self = @This();

        // grumble grumble
        // we don't have tight control over struct layout in Zig
        // which means these heads and tails will probably
        // all end up on the same cache line, which might
        // cause some minor perf hits due to false sharing.

        frontHead: u32,
        backHead: u32,
        frontTail: u32,
        backTail: u32,
        buffer: [N]T,

        pub fn init() Self {
            return Self{
                .frontHead = 0,
                .backHead = 0,
                .frontTail = N - 1,
                .backTail = N - 1,
                .buffer = undefined,
            };
        }

        pub fn enqueue(self: *Self, value: T) error{QueueFull}!void {
            // get a slot
            var nextHead: u32 = undefined;
            var head = @atomicLoad(u32, &self.frontHead, .SeqCst);
            while (true) {
                // reload the tail after loading the head to ensure head >= tail
                var tail = @atomicLoad(u32, &self.backTail, .SeqCst);

                // check for full
                if (head == tail) {
                    // if reads are in progress, wait for a free slot.
                    if (head != @atomicLoad(u32, &self.frontTail, .SeqCst)) continue;
                    return error.QueueFull;
                }

                // calc next head
                nextHead = head + 1;
                if (nextHead == N) nextHead = 0;

                // cmpxchg next head
                if (@cmpxchgWeak(u32, &self.frontHead, head, nextHead, .SeqCst, .SeqCst)) |actualVal| {
                    head = actualVal;
                } else {
                    break;
                }
            }

            // copy the value
            self.buffer[head] = value;
            @fence(.SeqCst); // ensure write has completed and buffer is safe to read

            // move the back head once previous writes are done
            while (@cmpxchgWeak(u32, &self.backHead, head, nextHead, .SeqCst, .SeqCst)) |_| {}
        }

        pub fn dequeue(self: *Self) error{QueueEmpty}!T {
            var value: T = undefined;
            {
                // get a slot
                var tail: u32 = undefined;
                var lastTail = @atomicLoad(u32, &self.frontTail, .SeqCst);
                while (true) {
                    // reload the head after loading the tail to ensure head >= tail
                    var head = @atomicLoad(u32, &self.backHead, .SeqCst);
                    // calculate next tail pos
                    tail = lastTail + 1;
                    if (tail == N) tail = 0;

                    // check for empty
                    if (tail == head) {
                        // if writes are in progress, wait for one to complete.
                        if (tail != @atomicLoad(u32, &self.frontHead, .SeqCst)) continue;
                        return error.QueueEmpty;
                    }

                    // cmpxchg next tail
                    if (@cmpxchgWeak(u32, &self.frontTail, lastTail, tail, .SeqCst, .SeqCst)) |actualVal| {
                        lastTail = actualVal;
                    } else {
                        break;
                    }
                }

                // copy the value
                value = self.buffer[tail];
                @fence(.SeqCst); // ensure read has completed and buffer is safe to modify

                // move the back tail once previous reads are done
                while (@cmpxchgWeak(u32, &self.backTail, lastTail, tail, .SeqCst, .SeqCst)) |_| {}
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

const queue_size = 64;

const Context = struct {
    allocator: *std.mem.Allocator,
    queue: *InstantQueue(i32, queue_size),
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
const puts_per_thread = 5000;
const put_thread_count = 3;

test "std.atomic.Queue" {
    var plenty_of_memory = try std.heap.direct_allocator.alloc(u8, 300 * 1024);
    defer std.heap.direct_allocator.free(plenty_of_memory);

    var fixed_buffer_allocator = std.heap.ThreadSafeFixedBufferAllocator.init(plenty_of_memory);
    var a = &fixed_buffer_allocator.allocator;

    var queue = InstantQueue(i32, queue_size).init();
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
    var fullCount: u24 = 0;
    while (put_count != 0) : (put_count -= 1) {
        std.time.sleep(1); // let the os scheduler be our fuzz
        const x = @bitCast(i32, r.random.scalar(u32));
        while (true) {
            if (ctx.queue.enqueue(x)) {
                _ = @atomicRmw(isize, &ctx.put_sum, builtin.AtomicRmwOp.Add, x, AtomicOrder.SeqCst);
                break;
            } else |err| {
                fullCount +%= 1;
                if (fullCount == 0) {
                    std.debug.warn("queue full: {}\n", ctx.queue.*);
                }
            }
        }
    }
    return 0;
}

fn startGets(ctx: *Context) u8 {
    while (true) {
        const last = @atomicLoad(u8, &ctx.puts_done, builtin.AtomicOrder.SeqCst) == 1;
        var emptyCount: u24 = 0;

        while (ctx.queue.dequeue()) |data| {
            _ = @atomicRmw(isize, &ctx.get_sum, builtin.AtomicRmwOp.Add, data, builtin.AtomicOrder.SeqCst);
            _ = @atomicRmw(usize, &ctx.get_count, builtin.AtomicRmwOp.Add, 1, builtin.AtomicOrder.SeqCst);
        } else |err| {
            emptyCount +%= 1;
            if (emptyCount == 0) std.debug.warn("queue empty\n");
        }

        if (last) return 0;
    }
}
