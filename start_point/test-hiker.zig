const std = @import("std");
const assert = std.debug.assert;

const answer = @import("hiker.zig").answer;

test "the answer to life the universe and everything" {
    assert(answer() == 42);
}
