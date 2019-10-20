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

        /// frontHead is the next head index to write to
        /// backTail is one before the first safe tail index to write to
        /// These values must both be read atomically in enqueue, so they
        /// have been packed into one integer.
        frontHeadBackTail: u64,

        /// frontTail is one before the next tail index to read from
        /// backHead is the first safe head index to read from
        /// These values must both be read atomically in dequeue, so they
        /// have been packed into one integer.
        frontTailBackHead: u64,

        /// Data storage
        buffer: [N]T,

        pub fn init() Self {
            return Self{
                .frontHeadBackTail = N - 1,
                .frontTailBackHead = u64(N - 1) << 32,
                .buffer = undefined,
            };
        }

        /// NOT THREAD SAFE! Enqueues an item.
        pub fn enqueueUnsafe(self: *Self, value: T) error{QueueFull}!void {
            var head = self.frontHeadBackTail >> 32;
            const tail = self.frontHeadBackTail & 0xFFFFFFFF;

            if (head == tail)
                return error.QueueFull;

            self.buffer[head] = value;

            head += 1;
            if (head == N) head = 0;

            self.frontHeadBackTail = (head << 32) | tail;
            self.frontTailBackHead = (tail << 32) | head;
        }

        /// NOT THREAD SAFE! Dequeues an item.
        pub fn dequeueUnsafe(self: *Self) error{QueueEmpty}!T {
            var tail = self.frontHeadBackTail & 0xFFFFFFFF;
            const head = self.frontHeadBackTail >> 32;

            tail += 1;
            if (tail == N) tail = 0;

            if (tail == head)
                return error.QueueEmpty;

            self.frontHeadBackTail = (head << 32) | tail;
            self.frontTailBackHead = (tail << 32) | head;

            return self.buffer[tail];
        }

        /// Thread safe. Enqueues a single item. If the queue is full,
        /// returns error.QueueFull.
        pub fn enqueue(self: *Self, value: T) error{QueueFull}!void {
            // get a slot
            var nextHead: u32 = undefined;
            var head: u32 = undefined;
            {
                var fhbt = @atomicLoad(u64, &self.frontHeadBackTail, .SeqCst);
                while (true) {
                    // reload the tail after loading the head to ensure head >= tail
                    head = @truncate(u32, fhbt >> 32);
                    const tail = @truncate(u32, fhbt);

                    // check for full
                    if (head == tail) {
                        // if reads are in progress, wait for a free slot.
                        const ftbh = @atomicLoad(u64, &self.frontTailBackHead, .SeqCst);
                        const frontTail = @truncate(u32, ftbh >> 32);
                        if (head != frontTail) {
                            fhbt = @atomicLoad(u64, &self.frontHeadBackTail, .SeqCst);
                            continue;
                        }
                        return error.QueueFull;
                    }

                    // calc next head
                    nextHead = head + 1;
                    if (nextHead == N) nextHead = 0;

                    const nextFhbt = (u64(nextHead) << 32) | tail;

                    // cmpxchg next head
                    if (@cmpxchgWeak(u64, &self.frontHeadBackTail, fhbt, nextFhbt, .SeqCst, .SeqCst)) |actualVal| {
                        fhbt = actualVal;
                    } else {
                        break;
                    }
                }
            }

            // copy the value
            self.buffer[head] = value;
            @fence(.SeqCst); // ensure write has completed and buffer is safe to read

            // move the back head once previous writes are done
            {
                var ftbh = @atomicLoad(u64, &self.frontTailBackHead, .SeqCst);
                while (true) {
                    const lastFtbh = (ftbh & ~u64(0xFFFFFFFF)) | head;
                    const nextFtbh = (ftbh & ~u64(0xFFFFFFFF)) | nextHead;
                    if (@cmpxchgWeak(u64, &self.frontTailBackHead, lastFtbh, nextFtbh, .SeqCst, .SeqCst)) |actualVal| {
                        ftbh = actualVal;
                    } else {
                        break;
                    }
                }
            }
        }

        /// Thread safe. Dequeues a single item. If the queue is empty,
        /// returns error.QueueEmpty.
        pub fn dequeue(self: *Self) error{QueueEmpty}!T {
            var value: T = undefined;
            {
                // get a slot
                var tail: u32 = undefined;
                var lastTail: u32 = undefined;
                {
                    var ftbh = @atomicLoad(u64, &self.frontTailBackHead, .SeqCst);
                    while (true) {
                        // reload the tail after loading the head to ensure head >= tail
                        lastTail = @truncate(u32, ftbh >> 32);
                        const head = @truncate(u32, ftbh);

                        // calculate next tail pos
                        tail = lastTail + 1;
                        if (tail == N) tail = 0;

                        // check for empty
                        if (tail == head) {
                            // if reads are in progress, wait for a free slot.
                            const fhbt = @atomicLoad(u64, &self.frontHeadBackTail, .SeqCst);
                            const frontHead = @truncate(u32, fhbt >> 32);
                            if (tail != frontHead) {
                                ftbh = @atomicLoad(u64, &self.frontTailBackHead, .SeqCst);
                                continue;
                            }
                            return error.QueueEmpty;
                        }

                        const nextFtbh = (u64(tail) << 32) | head;

                        // cmpxchg next head
                        if (@cmpxchgWeak(u64, &self.frontTailBackHead, ftbh, nextFtbh, .SeqCst, .SeqCst)) |actualVal| {
                            ftbh = actualVal;
                        } else {
                            break;
                        }
                    }
                }

                // copy the value
                value = self.buffer[tail];
                @fence(.SeqCst); // ensure read has completed and buffer is safe to modify

                // move the back tail once previous reads are done
                {
                    var fhbt = @atomicLoad(u64, &self.frontHeadBackTail, .SeqCst);
                    while (true) {
                        const lastFhbt = (fhbt & ~u64(0xFFFFFFFF)) | lastTail;
                        const nextFhbt = (fhbt & ~u64(0xFFFFFFFF)) | tail;
                        if (@cmpxchgWeak(u64, &self.frontHeadBackTail, lastFhbt, nextFhbt, .SeqCst, .SeqCst)) |actualVal| {
                            fhbt = actualVal;
                        } else {
                            break;
                        }
                    }
                }
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
