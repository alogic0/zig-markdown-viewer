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
    cleanup_attempt=0
    while [ -e "${work_dir}" ] && [ "${cleanup_attempt}" -lt 100 ]; do
        rm -rf "${work_dir}" 2>/dev/null || true
        cleanup_attempt=$((cleanup_attempt + 1))
        if [ -e "${work_dir}" ]; then
            sleep 0.05
        fi
    done
    if [ -e "${work_dir}" ]; then
        echo "warning: could not completely remove ${work_dir}" >&2
    fi
}
trap cleanup EXIT HUP INT TERM

cp -R "${extension_dir}/." "${work_dir}/"
cp "${renderer_wasm}" "${work_dir}/renderer.wasm"
cp "${harness_html}" "${work_dir}/visual-math-e2e.html"
sed 's|chrome-extension://__MSG_@@extension_id__/css/fonts/ZigMathSTIX.woff2|./fonts/ZigMathSTIX.woff2|' \
    "${work_dir}/css/math.css" >"${work_dir}/css/math-harness.css"
sed 's|href="css/math.css"|href="css/math-harness.css"|' \
    "${work_dir}/visual-math-e2e.html" >"${work_dir}/visual-math-e2e.html.tmp"
mv "${work_dir}/visual-math-e2e.html.tmp" "${work_dir}/visual-math-e2e.html"

if ! "${browser}" \
    --headless=new \
    --no-sandbox \
    --disable-gpu \
    --disable-background-networking \
    --allow-file-access-from-files \
    --window-size=1280,900 \
    --user-data-dir="${work_dir}/profile" \
    --virtual-time-budget=30000 \
    --dump-dom \
    "file://${work_dir}/visual-math-e2e.html" \
    >"${work_dir}/dom.html" 2>"${work_dir}/chromium.log"
then
    printf '%s\n' \
        '::error title=Chromium visual-math process::Chromium exited before producing a test result; see the browser log in this step.' >&2
    "${browser}" --version >&2 || true
    cat "${work_dir}/chromium.log" >&2
    exit 1
fi

if ! rg -F 'data-e2e-status="pass"' "${work_dir}/dom.html" >/dev/null; then
    e2e_error="$(rg -o 'data-e2e-error="[^"]*"' "${work_dir}/dom.html" | sed 's/^data-e2e-error="//; s/"$//' | sed -n '1p' || true)"
    if [ -n "${e2e_error}" ]; then
        printf '::error title=Chromium visual-math assertion::%s\n' "${e2e_error}" >&2
    else
        printf '%s\n' \
            '::error title=Chromium visual-math assertion::The harness did not report a passing result or a specific assertion; inspect the dumped DOM in this step.' >&2
    fi
    "${browser}" --version >&2 || true
    cat "${work_dir}/dom.html" >&2
    cat "${work_dir}/chromium.log" >&2
    exit 1
fi

result="$(rg -o '<pre id="e2e-result">[^<]*' "${work_dir}/dom.html" | sed 's/^<pre id="e2e-result">//')"
echo "Chromium visual math E2E: ${result}"
