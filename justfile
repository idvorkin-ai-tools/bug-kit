# Shared entry points across Igor's native repos: just build, test, install, run.
# Build the package for the Mac.
build:
    swift build

# The host tests on the Mac.
test:
    swift test

# The Linux rung, on a Linux box (scripts/test-linux.sh says what it needs): the host tests run on Linux, then the
# package and its tests cross-built for macOS, iOS and the simulator with a Darwin Swift SDK. On a Mac: swift test.
test-linux:
    scripts/test-linux.sh
