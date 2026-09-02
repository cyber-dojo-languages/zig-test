#!/bin/bash
# Invoked as [bash install.sh], and that ignores the shebang line, so the shell
# options have to be set here to have any effect.
set -Eeu -o pipefail

# Warms zig's compilation cache, which the image did not ship at all. A kata
# runs in a container thrown away afterwards, so every [test] press started with
# an empty cache and recompiled the standard library and the test runner before
# it could get to the learner's code. That was most of the wait.
#
# The cache goes in the sandbox user's home because that is where zig looks for
# it: a kata runs as sandbox, and zig's global cache defaults to $HOME/.cache/zig.
# Putting it there means cyber-dojo.sh needs no environment variable naming it.

readonly WORK_DIR=/tmp/warm_zig_cache
readonly SANDBOX_HOME=/home/sandbox

mkdir -p "${WORK_DIR}" && cd "${WORK_DIR}"

# Shaped like a real kata, a source file and a test asserting against it, so the
# entries left behind are the ones a kata reaches for.
cat > hiker.zig << 'EOF'
pub fn answer() i32 {
    return 6 * 7;
}
EOF

cat > hiker_test.zig << 'EOF'
const std = @import("std");
const hiker = @import("hiker.zig");

test "life the universe and everything" {
    try std.testing.expectEqual(@as(i32, 42), hiker.answer());
}
EOF

# -fstrip matches what cyber-dojo.sh runs. A cache entry is keyed on the flags
# that produced it, so warming with different ones would leave a cache a kata
# cannot use.
HOME="${SANDBOX_HOME}" zig test -fstrip hiker_test.zig

# A kata runs as sandbox and must be able to read what was cached here, and to
# add to it as the learner's own code changes.
chown -R sandbox:sandbox "${SANDBOX_HOME}/.cache"
du -sm "${SANDBOX_HOME}/.cache/zig"

# A cache is keyed on the compiler and the flags that filled it. If those ever
# drift from what cyber-dojo.sh runs, zig silently recompiles and the press is
# merely as slow as it was before. This compares a run against the warmed cache
# with one against an empty one, and insists the warm run be several times
# quicker.
#
# The comparison is against a cold run rather than a fixed number of seconds
# because this same script runs under QEMU when the arm64 half of the image is
# built on an amd64 machine. Emulated, a warm run takes seconds where it takes a
# fraction of one natively, so any threshold that fits one fails the other. A
# ratio holds either way: both runs are slowed by the same emulation.
zig_test_seconds()
{
  local -r cache_dir="${1}"
  { TIMEFORMAT='%3R'; time ZIG_GLOBAL_CACHE_DIR="${cache_dir}" zig test -fstrip hiker_test.zig > /dev/null 2>&1; } 2>&1
}

readonly COLD_SECONDS=$(zig_test_seconds /tmp/cold-zig-cache)
readonly WARM_SECONDS=$(zig_test_seconds "${SANDBOX_HOME}/.cache/zig")
echo "[zig test] cold ${COLD_SECONDS}s, warm ${WARM_SECONDS}s"
rm -rf /tmp/cold-zig-cache

if [ "$(echo "${COLD_SECONDS} > ${WARM_SECONDS} * 2" | bc -l)" != '1' ]; then
  >&2 echo "Expected a warmed cache to be several times quicker than an empty one."
  >&2 echo "The cache is not being hit, so a kata's first press will recompile."
  exit 42
fi

# Left owned by sandbox after the timing runs above, which ran as root.
chown -R sandbox:sandbox "${SANDBOX_HOME}/.cache"

cd /
rm -rf "${WORK_DIR}"
