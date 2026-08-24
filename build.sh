#!/bin/sh
set -eu

viewer_zig_exe="${ZIG_EXE:-${HOME}/.zig/0.17.0-dev.1756+613c03321/files/zig}"

if [ ! -x "${viewer_zig_exe}" ]; then
    echo "required Zig compiler not found: ${viewer_zig_exe}" >&2
    exit 1
fi

exec "${viewer_zig_exe}" build "$@"

