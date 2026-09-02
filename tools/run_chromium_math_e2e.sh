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
browser_pid=""
cleanup() {
    if [ -n "${browser_pid}" ]; then
        kill "${browser_pid}" 2>/dev/null || true
        wait "${browser_pid}" 2>/dev/null || true
    fi
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

"${browser}" \
    --headless=new \
    --no-sandbox \
    --disable-gpu \
    --disable-background-networking \
    --allow-file-access-from-files \
    --no-first-run \
    --window-size=1280,900 \
    --user-data-dir="${work_dir}/profile" \
    --remote-debugging-port=0 \
    "file://${work_dir}/visual-math-e2e.html" \
    >"${work_dir}/chromium.out" 2>"${work_dir}/chromium.log" &
browser_pid="$!"

attempt=0
while [ ! -s "${work_dir}/profile/DevToolsActivePort" ] && [ "${attempt}" -lt 200 ]; do
    if ! kill -0 "${browser_pid}" 2>/dev/null; then
        printf '%s\n' \
            '::error title=Chromium visual-math process::Chromium exited before its DevTools endpoint started.' >&2
        "${browser}" --version >&2 || true
        cat "${work_dir}/chromium.log" >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    sleep 0.05
done
if [ ! -s "${work_dir}/profile/DevToolsActivePort" ]; then
    printf '%s\n' \
        '::error title=Chromium visual-math process::Chromium DevTools endpoint did not start.' >&2
    "${browser}" --version >&2 || true
    cat "${work_dir}/chromium.log" >&2
    exit 1
fi
debug_port="$(sed -n '1p' "${work_dir}/profile/DevToolsActivePort")"

attempt=0
while [ "${attempt}" -lt 600 ]; do
    if ! kill -0 "${browser_pid}" 2>/dev/null; then
        printf '%s\n' \
            '::error title=Chromium visual-math process::Chromium exited before the harness completed.' >&2
        "${browser}" --version >&2 || true
        cat "${work_dir}/chromium.log" >&2
        exit 1
    fi
    curl -s "http://127.0.0.1:${debug_port}/json/list" >"${work_dir}/targets.json" || true
    if rg -F '"title": "Zig math E2E PASS"' "${work_dir}/targets.json" >/dev/null; then
        echo "Chromium visual math E2E: pass"
        exit 0
    fi
    if rg -F '"title": "Zig math E2E FAIL:' "${work_dir}/targets.json" >/dev/null; then
        e2e_error="$(sed -n 's/^[[:space:]]*"title": "Zig math E2E FAIL: \(.*\)",$/\1/p' "${work_dir}/targets.json" | sed -n '1p')"
        printf '::error title=Chromium visual-math assertion::%s\n' "${e2e_error}" >&2
        "${browser}" --version >&2 || true
        cat "${work_dir}/targets.json" >&2
        cat "${work_dir}/chromium.log" >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    sleep 0.05
done

printf '%s\n' \
    '::error title=Chromium visual-math timeout::The harness did not complete within 30 seconds.' >&2
"${browser}" --version >&2 || true
cat "${work_dir}/targets.json" >&2
cat "${work_dir}/chromium.log" >&2
exit 1
