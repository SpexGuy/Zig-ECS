const std = @import("std");
const assert = std.debug.assert;
const AtomicInt = std.atomic.Int;
const SpinLock = std.SpinLock;
const Thread = std.Thread;
const Allocator = std.mem.Allocator;
const InstantQueue = @import("instant_queue.zig").InstantQueue;
const warn = std.debug.warn;

const util = @import("util.zig");
const pages = @import("pages.zig");

const NUM_JOBS = 32768;

const DEBUG_PERMITS = false;
const DEBUG_RTR = false;

pub const JobID = struct {
    value: u32,

    pub const Invalid = JobID{ .value = 0xFFFFFFFF };
};

const RawJobFunc = fn (JobInterface, [*]const u8) void;

pub const JobInterface = struct {
    jobSystem: *JobSystem,
    jobDesc: *JobSystem.JobDesc,
    jobID: JobID,

    pub fn addSubJob(self: JobInterface, param: var, comptime func: fn (JobInterface, @typeOf(param)) void) JobID {
        return self.addSubJobWithDeps(func, param, util.emptySlice(JobID));
    }

    pub fn addSubJobWithDeps(self: JobInterface, param: var, comptime func: fn (JobInterface, @typeOf(param)) void, deps: []const JobID) JobID {
        // @todo: This parent link opens up an opportunity for dependency cycles.
        // Such cycles will not be noticed until the entire system flushes.
        // We should add debug dependency cycle checks here.
        _ = self.jobDesc.dependencies.incr();
        const T = @typeOf(param);
        const rawFunc = adapterFunc(T, func);
        const job = self.jobSystem.obtainJob(rawFunc);
        self.jobSystem.setJobParam(job, param);
        job.permits.shortJobs[0] = JobSystem.getShortID(self.jobID);
        return self.jobSystem.publishJobWithDeps(job, deps);
    }
};

fn adapterFunc(comptime T: type, comptime func: fn (JobInterface, T) void) RawJobFunc {
    const Adapter = struct {
        fn adapt(job: JobInterface, rawParam: [*]const u8) void {
            if (@sizeOf(T) == 0) {
                var param = T{};
                func(job, param);
            } else {
                const paramPtr: *const T = @ptrCast(*const T, @alignCast(@alignOf(T), rawParam));
                func(job, paramPtr.*);
            }
        }
    };
    return Adapter.adapt;
}

pub const JobSystem = struct {
    const SHORT_JOB_INVALID: u16 = 0xFFFF;
    const PARAM_POS_EXTERNAL: u8 = 0xFF;

    const ShortJobQueue = InstantQueue(u16, NUM_JOBS + 64);

    mainThread: Thread.Id,
    state: SystemState,
    pendingJobs: AtomicInt(u16),
    threadState: []align(64) ThreadState,
    allocator: *Allocator,
    jobs: [NUM_JOBS]JobDesc align(64),
    freeJobs: ShortJobQueue,
    readyToRunJobs: ShortJobQueue,

    pub fn init(allocator: *Allocator) JobSystem {
        var self = JobSystem{
            .mainThread = Thread.getCurrentId(),
            .state = .NotStarted,
            .pendingJobs = AtomicInt(u16).init(0),
            .threadState = util.emptySlice(ThreadState),
            .allocator = allocator,
            .jobs = [1]JobDesc{JobDesc{
                .func = null,
                .lock = SpinLock.init(),
                .dependencies = AtomicInt(u8).init(0),
                .state = .Free,
                .paramPos = .Internal,
                .gen = 0,
                .permits = JobPermits.Empty,
                .paramData = undefined,
            }} ** NUM_JOBS,
            .freeJobs = ShortJobQueue.init(),
            .readyToRunJobs = ShortJobQueue.init(),
        };
        var job: u16 = 0;
        while (job < NUM_JOBS) : (job += 1) {
            self.freeJobs.enqueueUnsafe(job) catch unreachable;
        }
        return self;
    }

    pub fn startup(self: *JobSystem, numThreads: u32) !void {
        assert(self.mainThread == Thread.getCurrentId());
        assert(self.state == .NotStarted);
        self.state = .Running;

        self.threadState = try self.allocator.alloc(ThreadState, numThreads);
        errdefer {
            self.allocator.free(self.threadState);
            self.threadState = util.emptySlice(ThreadState);
        }

        var threadIndex: u32 = 0;

        errdefer {
            self.state = .ShuttingDown;
            // @todo: once we introduce the wait semaphore, post to it for each successful thread from here.
            for (self.threadState[0..threadIndex]) |context| {
                context.thread.wait();
            }
            self.state = .NotStarted;
        }

        while (threadIndex < numThreads) : (threadIndex += 1) {
            const state = &self.threadState[threadIndex];
            state.jobSystem = self;
            state.thread = try Thread.spawn(state, jobThread);
        }
    }

    pub fn flush(self: *JobSystem) void {
        assert(self.mainThread == Thread.getCurrentId());
        assert(self.state == .Running);
        var nextJob: u16 = SHORT_JOB_INVALID;
        while (self.pendingJobs.get() != 0) {
            // get the next job
            if (nextJob == SHORT_JOB_INVALID) {
                nextJob = self.waitForReadyTaskTimeout(1) catch continue;
            }
            nextJob = self.runSingleJob(nextJob);
        }
        assert(nextJob == SHORT_JOB_INVALID);
    }

    pub fn wait(self: *JobSystem, task: JobID) void {
        assert(self.mainThread == Thread.getCurrentId());
        assert(self.state == .Running);
        var nextJob: u16 = SHORT_JOB_INVALID;
        while (!self.isJobFinished(task)) {
            // get the next job
            if (nextJob == SHORT_JOB_INVALID) {
                nextJob = self.waitForReadyTaskTimeout(1) catch continue;
            }
            nextJob = self.runSingleJob(nextJob);
        }
        if (nextJob != SHORT_JOB_INVALID) {
            self.addReadyToRunJob(nextJob);
        }
    }

    pub fn shutdown(self: *JobSystem) void {
        assert(self.mainThread == Thread.getCurrentId());
        assert(self.state == .Running);
        self.state = .ShuttingDown;
        // @todo: once we introduce the wait semaphore, post to it for each thread from here.
        for (self.threadState) |context| {
            context.thread.wait();
        }
        self.pendingJobs.set(0);
        self.state = .Shutdown;

        self.allocator.free(self.threadState);
        self.threadState = util.emptySlice(ThreadState);
    }

    const ThreadState = struct {
        jobSystem: *JobSystem align(64),
        thread: *Thread,
        pad: [48]u8,
    };

    const ParamInternalSize = 40;
    const ParamInternalOffset = @byteOffsetOf(JobDesc, "paramData");

    const JobDesc = struct {
        // constant after publication
        paramData: [ParamInternalSize]u8 align(64),
        // constant after publication
        func: ?RawJobFunc,
        // constant
        lock: SpinLock,
        // set on creation, only decremented afterwards
        dependencies: AtomicInt(u8),
        // only modified by releasing when dependencies == 0
        state: JobState,
        // set on creation
        paramPos: ParamState,
        // protected by lock
        gen: u16,
        // protected by lock
        permits: JobPermits, // permits have no generation
    };

    const SystemState = enum(u8) {
        NotStarted,
        Running,
        ShuttingDown,
        Shutdown,
    };

    const JobState = enum(u8) {
        Free,
        NotStarted,
        WaitingForChildren,
    };

    const ParamState = enum(u8) {
        Internal,
        External,
    };

    const JobPermits = struct {
        shortJobs: [3]u16,
        expansion: u16,

        const Empty = JobPermits{
            .shortJobs = [_]u16{
                SHORT_JOB_INVALID,
                SHORT_JOB_INVALID,
                SHORT_JOB_INVALID,
            },
            .expansion = SHORT_JOB_INVALID,
        };
    };

    pub fn schedule(self: *JobSystem, param: var, comptime func: fn (JobInterface, @typeOf(param)) void) JobID {
        return self.scheduleWithDeps(param, func, util.emptySlice(JobID));
    }

    pub fn scheduleWithDeps(self: *JobSystem, param: var, comptime func: fn (JobInterface, @typeOf(param)) void, deps: []const JobID) JobID {
        const T = @typeOf(param);
        const rawFunc = adapterFunc(T, func);
        const job = self.obtainJob(rawFunc);
        self.setJobParam(job, param);
        return self.publishJobWithDeps(job, deps);
    }

    fn publishJobWithDeps(self: *JobSystem, job: *JobDesc, deps: []const JobID) JobID {
        const jobID = self.findJobIDUnpublished(job);
        const shortID = getShortID(jobID);
        job.dependencies.set(@intCast(u8, 1 + deps.len)); // increment dependencies for this process
        for (deps) |dep| {
            if (dep.value == JobID.Invalid.value or
                !self.safeAddPermitToJob(dep, shortID))
                _ = job.dependencies.decr();
        }

        const remainingDeps = job.dependencies.decr();
        if (remainingDeps == 1) {
            self.addReadyToRunJob(shortID);
        }

        return jobID;
    }

    fn isJobFinished(self: *JobSystem, jobID: JobID) bool {
        const job = self.getJobDescShort(getShortID(jobID));
        const gen = getGeneration(jobID);
        const lock = job.lock.acquire();
        const jobGen = job.gen;
        lock.release();
        return jobGen != gen;
    }

    /// Returns true if the permit was added, false if the job has completed.
    fn safeAddPermitToJob(self: *JobSystem, jobID: JobID, permit: u16) bool {
        var job = self.getJobDescShort(getShortID(jobID));
        var lock = job.lock.acquire();
        if (getGeneration(jobID) == job.gen) {
            while (true) {
                // look for a blank slot
                for (job.permits.shortJobs) |*shortJob, i| {
                    if (shortJob.* == SHORT_JOB_INVALID) {
                        if (DEBUG_PERMITS) warn("adding permit {} to {}[{}] ({})\n", permit, self.findShortJobID(job), i, getShortID(jobID));
                        shortJob.* = permit;
                        lock.release();
                        return true;
                    }
                }
                // couldn't find a blank slot, look in the expansion slot
                // create an expansion if we need one
                var newJob: *JobDesc = undefined;
                if (job.permits.expansion == SHORT_JOB_INVALID) {
                    newJob = self.obtainExpansionSlotJob();
                    const newJobShortID = self.findShortJobID(newJob);
                    job.permits.expansion = newJobShortID;
                    if (DEBUG_PERMITS) warn("adding expansion {} to {} ({})\n", newJobShortID, self.findShortJobID(job), getShortID(jobID));
                } else {
                    newJob = self.getJobDescShort(job.permits.expansion);
                }
                // lock the expansion then unlock this job
                const newLock = newJob.lock.acquire();
                lock.release();
                lock = newLock;
                job = newJob;
            }
        } else {
            lock.release();
            return false;
        }
    }

    fn jobThread(state: *ThreadState) void {
        const self = state.jobSystem;
        var nextJob: u16 = SHORT_JOB_INVALID;

        // set the job as completed to freeze the permits list
        while (self.state != .ShuttingDown) {
            // get the next job
            if (nextJob == SHORT_JOB_INVALID) {
                nextJob = self.waitForReadyTask() catch break;
            }
            nextJob = self.runSingleJob(nextJob);
        }
    }

    fn runSingleJob(self: *JobSystem, jobID: u16) u16 {
        var job = self.getJobDescShort(jobID);

        // prepare to run.  Since the job is ready to run,
        // we know that there are no references to it,
        // so we can safely modify its state and dependency count.
        const oldValue = job.dependencies.xchg(1); // ensure deps won't hit zero during the job
        job.state = .WaitingForChildren;
        assert(oldValue == 0);
        const interface = JobInterface{
            .jobSystem = self,
            .jobDesc = job,
            .jobID = self.findJobIDUnpublished(job),
        };

        switch (job.paramPos) {
            .Internal => {
                const jobParam: [*]const u8 = &job.paramData;
                job.func.?(interface, jobParam); // may increment dependencies
            },
            .External => {
                var externalParam: []const u8 = undefined;
                @memcpy(@ptrCast([*]u8, &externalParam), &job.paramData, @sizeOf(@typeOf(externalParam)));
                job.func.?(interface, externalParam.ptr);
                self.allocator.free(externalParam);
            },
        }

        return self.releasePermits(job, jobID);
    }

    fn releasePermits(self: *JobSystem, job: *JobDesc, jobID: u16) u16 {
        var nextJob: u16 = SHORT_JOB_INVALID;

        const remainingDeps = job.dependencies.decr();
        if (DEBUG_PERMITS) warn("release permits for {}, {} deps remain\n", jobID, remainingDeps - 1);

        if (remainingDeps == 1) {
            switch (job.state) {
                .NotStarted => {
                    if (DEBUG_PERMITS) warn("moving {} to .WaitingForChildren\n", jobID);
                    job.state = .WaitingForChildren;
                    nextJob = jobID;
                },
                .WaitingForChildren => {
                    if (DEBUG_PERMITS) warn("freeing {}\n", jobID);
                    var lock = job.lock.acquire();
                    const nextPermits = job.permits;
                    job.gen +%= 1;
                    job.state = .Free;
                    job.permits = JobPermits.Empty;
                    lock.release();

                    self.addToFreeList(jobID);

                    for (nextPermits.shortJobs) |nextPermit| {
                        if (nextPermit != SHORT_JOB_INVALID) {
                            const parentJob = self.getJobDescShort(nextPermit);
                            const releaseJob = self.releasePermits(parentJob, nextPermit);
                            if (nextJob == SHORT_JOB_INVALID) {
                                nextJob = releaseJob;
                            } else if (releaseJob != SHORT_JOB_INVALID) {
                                self.addReadyToRunJob(releaseJob);
                            }
                        }
                    }
                    if (nextPermits.expansion != SHORT_JOB_INVALID) {
                        const expansionJob = self.getJobDescShort(nextPermits.expansion);
                        const releaseJob = self.releasePermits(expansionJob, nextPermits.expansion);
                        if (nextJob == SHORT_JOB_INVALID) {
                            nextJob = releaseJob;
                        } else if (releaseJob != SHORT_JOB_INVALID) {
                            self.addReadyToRunJob(releaseJob);
                        }
                    }
                },
                .Free => unreachable,
            }
        }

        return nextJob;
    }

    fn waitForReadyTask(self: *JobSystem) error{ShuttingDown}!u16 {
        // @todo: Use a semaphore here to avoid burning power
        while (self.state != .ShuttingDown) {
            if (self.readyToRunJobs.dequeue()) |shortID| {
                if (DEBUG_RTR) warn("pulled from RTR: {}\n", shortID);
                return shortID;
            } else |err| {
                continue;
            }
        }
        return error.ShuttingDown;
    }

    // @todo: document timeout units
    fn waitForReadyTaskTimeout(self: *JobSystem, timeout: u32) error{TimedOut}!u16 {
        // @todo: Use a semaphore here to avoid burning power
        var triesLeft = timeout;
        while (triesLeft > 0) : (triesLeft -= 1) {
            if (self.readyToRunJobs.dequeue()) |shortID| {
                if (DEBUG_RTR) warn("pulled from RTR: {}\n", shortID);
                return shortID;
            } else |err| {
                continue;
            }
        }
        return error.TimedOut;
    }

    fn addReadyToRunJob(self: *JobSystem, shortID: u16) void {
        if (DEBUG_RTR) warn("add to RTR: {}\n", shortID);
        // the RTR queue is big enough to hold all jobs, so we cannot fill it.
        self.readyToRunJobs.enqueue(shortID) catch {
            warn("ERROR: self=\n{}\n", self.*);
            unreachable;
        };
    }

    fn jobExpansionFunc(job: JobInterface, param: [*]const u8) void {
        unreachable;
    }

    fn obtainExpansionSlotJob(self: *JobSystem) *JobDesc {
        const shortID = self.freeJobs.dequeue() catch {
            warn("ERROR: self=\n{}\n", self.*);
            std.debug.panic("No more jobs for an expansion slot!");
        };
        _ = self.pendingJobs.incr();
        const job = self.getJobDescShort(shortID);
        assert(job.state == .Free);
        job.state = .WaitingForChildren;
        job.func = jobExpansionFunc;
        job.dependencies.set(1);
        return job;
    }

    fn obtainJob(self: *JobSystem, func: RawJobFunc) *JobDesc {
        const shortID = self.freeJobs.dequeue() catch {
            warn("ERROR: self=\n{}\n", self.*);
            std.debug.panic("No more jobs!");
        };
        _ = self.pendingJobs.incr();
        const job = self.getJobDescShort(shortID);
        assert(job.state == .Free);
        job.state = .NotStarted;
        job.func = func;
        return job;
    }

    fn setJobParam(self: *JobSystem, job: *JobDesc, param: var) void {
        const T = @typeOf(param);
        const size = @sizeOf(T);
        const alignment = @alignOf(T);
        if (size == 0) {
            job.paramPos = .Internal;
        } else {
            const rawParam = @ptrCast([*]const u8, &param);
            if (size <= ParamInternalSize and util.isAlignedPtr(&job.paramData, alignment)) {
                @memcpy(&job.paramData, rawParam, size);
                job.paramPos = .Internal;
            } else {
                // allocate the new value
                const slice = self.allocator.alignedAlloc(u8, alignment, size) catch std.debug.panic("Out of memory for job param!");
                // copy param data to the new allocation
                @memcpy(slice.ptr, rawParam, size);
                // copy slice data into job param
                const sliceSize = @sizeOf(@typeOf(slice));
                comptime assert(sliceSize <= ParamInternalSize);
                @memcpy(&job.paramData, @ptrCast([*]const u8, &slice), sliceSize);
                job.paramPos = .External;
            }
        }
    }

    fn addToFreeList(self: *JobSystem, shortID: u16) void {
        _ = self.pendingJobs.decr();
        // freeJobs contains enough entries to hold every job
        // so it cannot possibly be full unless we fucked up and
        // double-enqueued a job.
        self.freeJobs.enqueue(shortID) catch unreachable;
    }

    fn findShortJobID(self: *JobSystem, job: *JobDesc) u16 {
        const index = @intCast(u32, util.ptrDiff(&self.jobs, job)) / @sizeOf(JobDesc);
        assert(index < self.jobs.len);
        return @intCast(u16, index);
    }

    fn findJobIDUnpublished(self: *JobSystem, job: *JobDesc) JobID {
        const index = self.findShortJobID(job);
        const gen = job.gen;
        const jobValue: u32 = (u32(gen) << 16) | index;
        return JobID{ .value = jobValue };
    }

    fn getJobDescShort(self: *JobSystem, shortID: u16) *JobDesc {
        return &self.jobs[shortID];
    }

    fn getShortID(id: JobID) u16 {
        return @truncate(u16, id.value);
    }

    fn getGeneration(id: JobID) u16 {
        return @truncate(u16, id.value >> 16);
    }

    comptime {
        assert(@sizeOf(JobDesc) == 64);
        assert(@sizeOf(ThreadState) == 64);
        assert(ParamInternalOffset == 0);
    }
};

test "job system" {
    const allocator = std.heap.direct_allocator;

    var system = JobSystem.init(allocator);
    try system.startup(@intCast(u32, Thread.cpuCount() catch 4) - 1);

    var c: u32 = 0;
    while (c < 5000) : (c += 1) {
        var print0 = system.schedule("In a job!"[0..], printJob);
        var print1 = system.scheduleWithDeps("In job 2!"[0..], printJob, [_]JobID{print0});
        _ = system.scheduleWithDeps("INVALID"[0..], printSubJob, [_]JobID{print1});
        _ = system.scheduleWithDeps("invalid"[0..], printSubJob, [_]JobID{print1});
        _ = system.scheduleWithDeps("invalid"[0..], printSubJob, [_]JobID{print1});
        _ = system.scheduleWithDeps("invalid"[0..], printSubJob, [_]JobID{print1});
        _ = system.scheduleWithDeps("invalid"[0..], printSubJob, [_]JobID{print1});
        _ = system.scheduleWithDeps("invalid"[0..], printSubJob, [_]JobID{print1});
        _ = system.scheduleWithDeps("invalid"[0..], printSubJob, [_]JobID{print1});
        _ = system.scheduleWithDeps("invalid"[0..], printSubJob, [_]JobID{print1});
        _ = system.scheduleWithDeps("invalid"[0..], printSubJob, [_]JobID{print1});
        _ = system.scheduleWithDeps("invalid"[0..], printSubJob, [_]JobID{print1});
        _ = system.scheduleWithDeps("invalid"[0..], printSubJob, [_]JobID{print1});
        _ = system.scheduleWithDeps("invalid"[0..], printSubJob, [_]JobID{print1});
        _ = system.scheduleWithDeps("invalid"[0..], printSubJob, [_]JobID{print1});
        _ = system.scheduleWithDeps("invalid"[0..], printSubJob, [_]JobID{print1});
        _ = system.scheduleWithDeps("invalid"[0..], printSubJob, [_]JobID{print1});
        system.flush();
    }
    system.shutdown();
}

fn printSubJob(job: JobInterface, str: []const u8) void {
    const SubJob = struct {
        fn exec(_: JobInterface, char: u8) void {
            //std.debug.warn("{c} ", char);
        }
        fn finish(_: JobInterface, param: util.EmptyStruct) void {
            //std.debug.warn("\n");
        }
    };

    var chain = JobID.Invalid;
    for (str) |char| {
        chain = job.addSubJobWithDeps(char, SubJob.exec, [_]JobID{chain});
    }
    _ = job.addSubJobWithDeps(util.EmptyStruct{}, SubJob.finish, [_]JobID{chain});
}

fn printJob(job: JobInterface, str: []const u8) void {
    //std.debug.warn("{}\n", str);
}
