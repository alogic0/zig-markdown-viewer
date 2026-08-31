#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: run_chromium_source_e2e.sh EXTENSION_DIR RENDERER_WASM SERVER_SCRIPT" >&2
    exit 2
fi

extension_dir="$1"
renderer_wasm="$2"
server_script="$3"
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
    echo "Chromium source-viewer integration test requires Chrome or Chromium; set CHROME_EXE" >&2
    exit 1
fi

work_dir="$(mktemp -d)"
server_pid=""
browser_pid=""
cleanup() {
    if [ -n "${browser_pid}" ]; then
        kill "${browser_pid}" 2>/dev/null || true
        wait "${browser_pid}" 2>/dev/null || true
    fi
    if [ -n "${server_pid}" ]; then
        kill "${server_pid}" 2>/dev/null || true
        wait "${server_pid}" 2>/dev/null || true
    fi
    rm -r "${work_dir}"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "${work_dir}/extension"
mkdir -p "${work_dir}/downloads"
cp -R "${extension_dir}/." "${work_dir}/extension/"
cp "${renderer_wasm}" "${work_dir}/extension/renderer.wasm"

node "${server_script}" >"${work_dir}/port" 2>"${work_dir}/server.log" &
server_pid="$!"
attempt=0
while [ ! -s "${work_dir}/port" ] && [ "${attempt}" -lt 100 ]; do
    if ! kill -0 "${server_pid}" 2>/dev/null; then
        cat "${work_dir}/server.log" >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    sleep 0.05
done
if [ ! -s "${work_dir}/port" ]; then
    echo "source-viewer test server did not start" >&2
    exit 1
fi
port="$(sed -n '1p' "${work_dir}/port")"

"${browser}" \
    --headless=new \
    --no-sandbox \
    --disable-gpu \
    --no-first-run \
    --disable-default-apps \
    --download-default-directory="${work_dir}/downloads" \
    --disable-features=DisableLoadExtensionCommandLineSwitch,DisableDisableExtensionsExceptCommandLineSwitch \
    --disable-extensions-except="${work_dir}/extension" \
    --load-extension="${work_dir}/extension" \
    --user-data-dir="${work_dir}/profile" \
    --remote-debugging-port=0 \
    about:blank \
    >"${work_dir}/chromium.out" 2>"${work_dir}/chromium.log" &
browser_pid="$!"

attempt=0
while [ ! -s "${work_dir}/profile/DevToolsActivePort" ] && [ "${attempt}" -lt 200 ]; do
    if ! kill -0 "${browser_pid}" 2>/dev/null; then
        cat "${work_dir}/chromium.log" >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    sleep 0.05
done
if [ ! -s "${work_dir}/profile/DevToolsActivePort" ]; then
    echo "Chromium DevTools endpoint did not start" >&2
    exit 1
fi
debug_port="$(sed -n '1p' "${work_dir}/profile/DevToolsActivePort")"

attempt=0
while [ "${attempt}" -lt 200 ]; do
    if curl -s "http://127.0.0.1:${debug_port}/json/list" | rg -F '/js/background.js' >/dev/null; then
        break
    fi
    attempt=$((attempt + 1))
    sleep 0.05
done
if [ "${attempt}" -eq 200 ]; then
    echo "source-viewer service worker did not start" >&2
    cat "${work_dir}/chromium.log" >&2
    exit 1
fi
# The service-worker target is visible before its asynchronous dynamic-rule
# update callback completes. Give that one startup operation a bounded moment
# before creating the navigation under test.
sleep 1

source_url="http://127.0.0.1:${port}/sample.zig"
curl -s -X PUT "http://127.0.0.1:${debug_port}/json/new?${source_url}" >"${work_dir}/opened.json"

attempt=0
while [ "${attempt}" -lt 200 ]; do
    curl -s "http://127.0.0.1:${debug_port}/json/list" >"${work_dir}/targets.json"
    if rg -F '"title": "sample.zig · Zig Markdown Viewer"' "${work_dir}/targets.json" >/dev/null &&
        rg -F '/source.html#http://127.0.0.1:' "${work_dir}/targets.json" >/dev/null
    then
        break
    fi
    attempt=$((attempt + 1))
    sleep 0.05
done
if [ "${attempt}" -eq 200 ]; then
    cat "${work_dir}/opened.json" >&2
    cat "${work_dir}/targets.json" >&2
    cat "${work_dir}/chromium.log" >&2
    exit 1
fi

curl -s "http://127.0.0.1:${port}/requests" >"${work_dir}/requests.json"
if ! rg -F '"count":1' "${work_dir}/requests.json" >/dev/null ||
    ! rg -F '"accept":"text/plain,text/*;q=0.9,*/*;q=0.1"' "${work_dir}/requests.json" >/dev/null
then
    cat "${work_dir}/requests.json" >&2
    exit 1
fi
if find "${work_dir}" -name sample.zig -print | rg . >/dev/null; then
    echo "Chromium created an unexpected raw source download" >&2
    exit 1
fi

echo "Chromium source viewer E2E: attachment response rendered as highlighted Zig"
