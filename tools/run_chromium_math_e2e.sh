#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: run_chromium_math_e2e.sh EXTENSION_DIR RENDERER_WASM HARNESS_HTML" >&2
    exit 2
fi

extension_dir="$1"
renderer_wasm="$2"
harness_html="$3"
browser="${CHROME_EXE:-}"
if [ -z "${browser}" ]; then
    for candidate in google-chrome chromium chromium-browser; do
        if command -v "${candidate}" >/dev/null 2>&1; then
            browser="$(command -v "${candidate}")"
            break
        fi
    done
fi
if [ -z "${browser}" ]; then
    echo "Chromium visual-math integration test requires Chrome or Chromium; set CHROME_EXE" >&2
    exit 1
fi

work_dir="$(mktemp -d)"
cleanup() {
    rm -r "${work_dir}"
}
trap cleanup EXIT HUP INT TERM

cp -R "${extension_dir}/." "${work_dir}/"
cp "${renderer_wasm}" "${work_dir}/renderer.wasm"
cp "${harness_html}" "${work_dir}/visual-math-e2e.html"

if ! "${browser}" \
    --headless=new \
    --no-sandbox \
    --disable-gpu \
    --disable-background-networking \
    --allow-file-access-from-files \
    --window-size=1280,900 \
    --user-data-dir="${work_dir}/profile" \
    --virtual-time-budget=10000 \
    --dump-dom \
    "file://${work_dir}/visual-math-e2e.html" \
    >"${work_dir}/dom.html" 2>"${work_dir}/chromium.log"
then
    cat "${work_dir}/chromium.log" >&2
    exit 1
fi

if ! rg -F 'data-e2e-status="pass"' "${work_dir}/dom.html" >/dev/null; then
    cat "${work_dir}/dom.html" >&2
    cat "${work_dir}/chromium.log" >&2
    exit 1
fi

result="$(rg -o '<pre id="e2e-result">[^<]*' "${work_dir}/dom.html" | sed 's/^<pre id="e2e-result">//')"
echo "Chromium visual math E2E: ${result}"
