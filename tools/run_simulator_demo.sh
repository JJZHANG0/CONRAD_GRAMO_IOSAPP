#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Prefer an already-booted iPhone simulator; otherwise use an available iPhone.
# GRAMO_SIM_ID selects an explicit device. Keep NOMI_SIM_ID as a compatibility alias.
NOMI_SIM_ID="${GRAMO_SIM_ID:-${NOMI_SIM_ID:-}}"
if [[ -z "$NOMI_SIM_ID" ]]; then
  NOMI_SIM_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; ds=[d for runtime,items in json.load(sys.stdin)["devices"].items() if "iOS-" in runtime and int(runtime.split("iOS-")[-1].split("-")[0]) >= 18 for d in items if d["name"].startswith("iPhone")]; ds.sort(key=lambda d: d["state"] != "Booted"); assert ds,"Install an iPhone simulator runtime in Xcode first"; print(ds[0]["udid"])')
fi
NOMI_BUILD_DIR="$PWD/artifacts/simulator-build"
NOMI_LOG_DIR="$PWD/artifacts/simulator-evidence"
mkdir -p "$NOMI_LOG_DIR"
# simctl operates on an iOS Simulator only. Never calls devicectl or a serial tool.
NOMI_SIM_STATE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; ds=json.load(sys.stdin)["devices"]; match=[x for xs in ds.values() for x in xs if x["udid"]==sys.argv[1]]; assert len(match)==1,"Simulator ID not found"; print(match[0]["state"])' "$NOMI_SIM_ID")
if [[ "$NOMI_SIM_STATE" != "Booted" ]]; then xcrun simctl boot "$NOMI_SIM_ID"; fi
xcrun simctl bootstatus "$NOMI_SIM_ID" -b
xcodebuild -project GRAMO_APP.xcodeproj -scheme GRAMO_APP -configuration Debug \
  -destination "platform=iOS Simulator,id=$NOMI_SIM_ID" -derivedDataPath "$NOMI_BUILD_DIR" \
  build > "$NOMI_LOG_DIR/build.log" 2>&1
xcrun simctl install "$NOMI_SIM_ID" "$NOMI_BUILD_DIR/Build/Products/Debug-iphonesimulator/GRAMO_APP.app"
# Debug build phase embeds the existing local evaluation model, when available.
xcrun simctl launch --terminate-running-process "$NOMI_SIM_ID" com.kanglaide.zhiweishao -mock-device
printf 'GRAMO_APP 模拟演示已启动；记录保存在独立模拟环境。\n日志：%s/build.log\n' "$NOMI_LOG_DIR"
