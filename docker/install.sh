#!/bin/bash
# Invoked as [bash install.sh], and that ignores the shebang line, so the shell
# options have to be set here to have any effect.
set -Eeu -o pipefail

# Warms zig's compilation cache, which the image did not ship at all. Almost all
# of a test-run is zig compiling its own standard library and test runner, not
# the learner's handful of files. A kata runs in a container thrown away
# afterwards, so that work was repeated in full every time.
#
# Two things make the warmed cache reachable from a kata.
#
# The first is the target, which has to be spelled out rather than detected.
# Zig keys its cache on the target, and a detected target carries the kernel
# version and cpu of the machine doing the detecting. Warmed with a detected
# target, the cache is keyed to the machine that built the image and every
# other machine recompiles from scratch, which is what makes this the one
# setting that has to match cyber-dojo.sh exactly.
#
# The second is that the files warmed with are deleted afterwards. Zig's cache
# manifest records the source files by path and re-stats them, so a source file
# left behind that matches what a kata compiles would be served in place of the
# learner's own, reporting the wrong result. Deleting them means a kata's own
# files are the only ones there, and the cache keeps only zig's compiled code.

readonly SANDBOX_DIR=/sandbox
readonly SANDBOX_HOME=/home/sandbox

# Must stay identical to the options in the start-point's cyber-dojo.sh.
readonly TARGET_OPTS=(-mcpu=baseline -target native-linux.5.10...5.10-musl)

mkdir -p "${SANDBOX_DIR}" && cd "${SANDBOX_DIR}"

# Shaped like a kata, a source file and a test asserting against it, so the
# compiled code left behind is what a kata reaches for. The contents differ from
# any start-point's, which the deletion below makes moot but costs nothing.
cat > hiker.zig << 'EOF'
pub fn answer() i32 {
    return 6 * 5;
}
EOF

cat > hiker_test.zig << 'EOF'
const std = @import("std");
const hiker = @import("hiker.zig");

test "the answer to life the universe and everything" {
    try std.testing.expectEqual(42, hiker.answer());
}
EOF

# -fstrip matches what cyber-dojo.sh runs. Compiled output is keyed on the flags
# that produced it, so warming with different ones would leave a cache a kata
# cannot use. The test fails, which is the point of the kata's starting state,
# so the exit status is not an error here.
HOME="${SANDBOX_HOME}" zig test -fstrip "${TARGET_OPTS[@]}" hiker_test.zig || true

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# A cache is keyed on the compiler and the flags that filled it. If those ever
# drift from what cyber-dojo.sh runs, zig recompiles from scratch and the
# test-run is merely as slow as it was before. This measures a run whose source
# differs from the one warmed with, which is the only case a kata ever presents,
# against the same run with an empty cache, and insists the warm run be clearly
# quicker. A cache that is not being hit scores about 1.
#
# The comparison is against a cold run rather than a fixed number of seconds
# because this same script runs under QEMU when the arm64 half of the image is
# built on an amd64 machine. Emulated, a warm run takes seconds where it takes a
# fraction of one natively, so any threshold that fits one fails the other. A
# ratio holds either way: both runs are slowed by the same emulation.
#
# The value is one no start-point uses. Whatever is compiled last is left in the
# cache complete, so compiling the answer that makes the kata's test pass would
# hand that one case a hit no learner's own work gets, and the green duration
# measured from it would flatter every other.
cat > hiker.zig << 'EOF'
pub fn answer() i32 {
    return 6 * 3;
}
EOF

zig_test_seconds()
{
  local -r cache_dir="${1}"
  { TIMEFORMAT='%3R'; time ZIG_GLOBAL_CACHE_DIR="${cache_dir}" zig test -fstrip "${TARGET_OPTS[@]}" hiker_test.zig > /dev/null 2>&1; } 2>&1
}

readonly COLD_SECONDS=$(zig_test_seconds /tmp/cold-zig-cache)
readonly WARM_SECONDS=$(zig_test_seconds "${SANDBOX_HOME}/.cache/zig")
echo "[zig test] cold ${COLD_SECONDS}s, warm ${WARM_SECONDS}s"
rm -rf /tmp/cold-zig-cache

if ! awk "BEGIN { exit !(${COLD_SECONDS} > ${WARM_SECONDS} * 1.5) }"; then
  >&2 echo "Expected a warmed cache to be clearly quicker than an empty one."
  >&2 echo "The cache is not being hit, so a kata's test-run will recompile."
  exit 42
fi

# The learner's files are the only ones a kata compiles.
rm -f "${SANDBOX_DIR}"/*.zig

# A kata runs as sandbox and must be able to read what was cached here, and to
# add to it as the learner's own code changes.
chown -R sandbox:sandbox "${SANDBOX_HOME}/.cache" "${SANDBOX_DIR}"
du -sm "${SANDBOX_HOME}/.cache/zig"
