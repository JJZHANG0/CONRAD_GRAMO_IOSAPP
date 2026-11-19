#!/bin/sh
# Xcode build phase. Weights stay local and are never committed to the public repo.
set -eu
OUTPUT="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/ChineseFood.mlmodelc"
if [ "${CONFIGURATION}" != Debug ]; then
    exit 0
fi
MODEL="${SRCROOT}/artifacts/chinese-food/ChineseFood.mlpackage"
if [ ! -d "$MODEL" ]; then
    echo 'note: Local evaluation model absent; manual dish entry remains available.'
    exit 0
fi
mkdir -p "$(dirname "$OUTPUT")"
xcrun coremlcompiler compile "$MODEL" "$(dirname "$OUTPUT")"
