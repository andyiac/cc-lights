#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

configuration="debug"
if [[ "${1:-}" == "--release" ]]; then
  configuration="release"
  shift
fi

echo "Building ClaudeCodeStatusLight (${configuration})..."
swift build -c "${configuration}" --product ClaudeCodeStatusLight --product cc-statusctl

bin_dir="$(swift build -c "${configuration}" --show-bin-path)"
app_bin="${bin_dir}/ClaudeCodeStatusLight"
ctl_bin="${bin_dir}/cc-statusctl"
app_name="CC Status Light"
app_dir=".build/run-local/${configuration}/${app_name}.app"
contents_dir="${app_dir}/Contents"
macos_dir="${contents_dir}/MacOS"
resources_dir="${contents_dir}/Resources"
bundled_app_bin="${macos_dir}/ClaudeCodeStatusLight"

if [[ ! -x "${app_bin}" ]]; then
  echo "Missing executable: ${app_bin}" >&2
  exit 1
fi

rm -rf "${app_dir}"
mkdir -p "${macos_dir}"
mkdir -p "${resources_dir}"
cp Resources/Info.plist "${contents_dir}/Info.plist"
cp Resources/AppIcon.icns "${resources_dir}/AppIcon.icns"
cp "${app_bin}" "${bundled_app_bin}"
if [[ -x "${ctl_bin}" ]]; then
  cp "${ctl_bin}" "${resources_dir}/cc-statusctl"
  chmod +x "${resources_dir}/cc-statusctl"
fi
chmod +x "${bundled_app_bin}"

echo "Built:"
echo "  App: ${app_dir}"
echo "  Executable: ${bundled_app_bin}"
if [[ -x "${ctl_bin}" ]]; then
  echo "  CLI: ${ctl_bin}"
fi

echo
echo "Creating/updating a test session for this directory..."
debug_session="$(pwd)"
"${ctl_bin}" idle --session "${debug_session}" --cwd "$(pwd)" --title "$(basename "$(pwd)")" --message "本地调试 session"

# app 退出时移除调试 session，避免残留一个灯（不能用 exec，否则 trap 不触发）
cleanup() {
  "${ctl_bin}" remove --session "${debug_session}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo
echo "Running ClaudeCodeStatusLight..."
"${bundled_app_bin}" "$@"
