#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: rasterize_formula_logo.sh INPUT_SVG SIZE OUTPUT_PNG" >&2
    exit 2
fi

logo_input="$1"
logo_size="$2"
logo_output="$3"
logo_browser="${CHROME_EXE:-}"

case "${logo_input}" in
    /*) ;;
    *) logo_input="$(pwd)/${logo_input}" ;;
esac
case "${logo_output}" in
    /*) ;;
    *) logo_output="$(pwd)/${logo_output}" ;;
esac

if [ -z "${logo_browser}" ]; then
    for logo_candidate in google-chrome chromium chromium-browser; do
        if command -v "${logo_candidate}" >/dev/null 2>&1; then
            logo_browser="${logo_candidate}"
            break
        fi
    done
fi

if [ -z "${logo_browser}" ]; then
    echo "formula logo rasterization requires Chrome or Chromium; set CHROME_EXE" >&2
    exit 1
fi

logo_log="${logo_output}.log"
if ! "${logo_browser}" \
    --headless=new \
    --no-sandbox \
    --disable-gpu \
    --hide-scrollbars \
    --screenshot="${logo_output}" \
    --window-size="${logo_size},${logo_size}" \
    "file://${logo_input}" >"${logo_log}" 2>&1
then
    cat "${logo_log}" >&2
    rm "${logo_log}"
    exit 1
fi
rm "${logo_log}"
