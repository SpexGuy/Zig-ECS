const std = @import("std");
const assert = std.debug.assert;

const pages = @import("pages.zig");

const MAX_PERMITS = 5;

const JobSystem = struct {
    pub const JobID = struct {
        value: u32,

        pub const Invalid = JobID{ .value = 0xFFFFFFFF };
    };

    pub const JobParam = @OpaqueType();
    pub const JobFunc = fn (*JobParam) void;

    pub fn scheduleRaw(func: JobFunc, param: *JobParam) JobID {}

    running: bool,

    pub fn init() JobSystem {
        return JobSystem{};
    }

    const SHORT_JOB_INVALID: u16 = 0xFFFF;
    const PERMIT_FINISHED: u16 = 0xFFFE;

    fn jobThread(self: *JobSystem) void {
        while (self.running) {
            const taskID = self.takeNextReadyTask();
            var job = self.getJobDescUnchecked(taskID);
            job.func(job.param);
            // set the job as completed to freeze the permits list
            while (self.running) {
                var nextPermit = @atomicRmw(u16, &job.permit, .Xchg, PERMIT_FINISHED, .AcqRel);
                self.freeJobDesc(job);
                if (nextPermit == SHORT_JOB_INVALID) break;
                job = self.getJobDescShort(nextPermit);
                const jobPermitsLeft = @atomicRmw(u16, &job.pendingPermits, .Sub, 1, .AcqRel);
                if (jobPermitsLeft == 0) {
                    job.func(job.param);
                }
            }
        }
    }

    const JobDesc = struct {
        func: JobFunc align(64),
        param: *JobParam,
        gen: u16,
        pendingPermits: u16,
        permit: u16, // permits have no generation
        pad: [24]u8,
    };

    comptime {
        assert(@sizeOf(JobDesc) == 64);
        assert(@alignOf(JobDesc) == 64);
    }
};

test "job system" {
    const system = JobSystem.init();
}
