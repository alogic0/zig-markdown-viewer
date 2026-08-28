#!/bin/sh
set -eu

viewer_zig_exe="${ZIG_EXE:-${HOME}/.zig/0.17.0-dev.1756+613c03321/files/zig}"

if [ ! -x "${viewer_zig_exe}" ]; then
    echo "required Zig compiler not found: ${viewer_zig_exe}" >&2
    exit 1
fi

# Zig handles --help before selecting a build step. Forward help following the
# render-html step explicitly so it reaches the renderer instead.
if [ "$#" -ge 2 ] && [ "$1" = "render-html" ]; then
    case "$2" in
        -h|--help)
            renderer_help_flag="$2"
            shift 2
            set -- render-html -- "${renderer_help_flag}" "$@"
            ;;
    esac
fi

exec "${viewer_zig_exe}" build "$@"
