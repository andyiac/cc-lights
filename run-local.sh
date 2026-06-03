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
app_name="Claude Code Status Light"
app_dir=".build/run-local/${configuration}/${app_name}.app"
contents_dir="${app_dir}/Contents"
macos_dir="${contents_dir}/MacOS"
bundled_app_bin="${macos_dir}/ClaudeCodeStatusLight"

if [[ ! -x "${app_bin}" ]]; then
  echo "Missing executable: ${app_bin}" >&2
  exit 1
fi

rm -rf "${app_dir}"
mkdir -p "${macos_dir}"
cp Resources/Info.plist "${contents_dir}/Info.plist"
cp "${app_bin}" "${bundled_app_bin}"
chmod +x "${bundled_app_bin}"

echo "Built:"
echo "  App: ${app_dir}"
echo "  Executable: ${bundled_app_bin}"
if [[ -x "${ctl_bin}" ]]; then
  echo "  CLI: ${ctl_bin}"
fi

echo
echo "Creating/updating a test session for this directory..."
"${ctl_bin}" idle --session "$(pwd)" --cwd "$(pwd)" --title "$(basename "$(pwd)")" --message "本地调试 session"
echo
echo "Running ClaudeCodeStatusLight..."
exec "${bundled_app_bin}" "$@"
