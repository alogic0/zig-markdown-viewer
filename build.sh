#!/bin/sh
set -eu

viewer_zig_version="0.17.0-dev.1756+613c03321"
viewer_zig_exe="${ZIG_EXE:-${HOME}/.zig/${viewer_zig_version}/files/zig}"

if [ ! -x "${viewer_zig_exe}" ]; then
    if [ -n "${ZIG_EXE:-}" ]; then
        echo "configured Zig compiler not found: ${viewer_zig_exe}" >&2
        exit 1
    fi
    viewer_path_zig="$(command -v zig || true)"
    if [ -n "${viewer_path_zig}" ] && [ -x "${viewer_path_zig}" ]; then
        viewer_zig_exe="${viewer_path_zig}"
    else
        echo "required Zig compiler not found: ${viewer_zig_exe}" >&2
        exit 1
    fi
fi

viewer_actual_zig_version="$("${viewer_zig_exe}" version)"
if [ "${viewer_actual_zig_version}" != "${viewer_zig_version}" ]; then
    echo "required Zig version ${viewer_zig_version}, found ${viewer_actual_zig_version} at ${viewer_zig_exe}" >&2
    exit 1
fi

viewer_math_dev=false
if [ "$#" -ge 1 ]; then
    case "$1" in
        math-dev)
            viewer_math_dev=true
            shift
            ;;
        pin-math)
            shift
            if [ "$#" -ne 0 ]; then
                echo "usage: ./build.sh pin-math" >&2
                exit 2
            fi
            exec "${viewer_zig_exe}" run tools/pin_math_dependency.zig -- "${viewer_zig_exe}"
            ;;
        package-version)
            shift
            exec "${viewer_zig_exe}" run tools/package_version.zig -- "$@"
            ;;
    esac
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

if [ "${viewer_math_dev}" = true ]; then
    set -- --fork ../zig-math-typesetter "$@"
fi

exec "${viewer_zig_exe}" build "$@"
