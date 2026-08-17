#!/usr/bin/env bash
set -euo pipefail

repo="https://github.com/nesrak1/AssetsTools.NET.git"
work_dir="${RUNNER_TEMP:-/tmp}/assetstools-api"
rm -rf "$work_dir"
git clone --depth 1 --quiet "$repo" "$work_dir"

assets_dir="$work_dir/AssetTools.NET"
grep -q 'LoadAssetsFile(string path' "$assets_dir/Extra/AssetsManager/AssetsManager.Assets.cs"
grep -q 'LoadBundleFile(string path' "$assets_dir/Extra/AssetsManager/AssetsManager.Bundle.cs"
grep -q 'GetBaseField(AssetsFileInstance inst, AssetFileInfo info' "$assets_dir/Extra/AssetsManager/AssetsManager.Deserialization.cs"
grep -q 'WriteToByteArray' "$assets_dir/Standard/AssetTypeClass/AssetTypeValueField.cs"
grep -q 'SetNewData(byte\[\])' "$assets_dir/Standard/AssetsFileFormat/AssetFileInfo.cs" || grep -q 'SetNewData(byte\[\] newBytes)' "$assets_dir/Standard/AssetsFileFormat/AssetFileInfo.cs"
grep -q 'public void Write(AssetsFileWriter writer' "$assets_dir/Standard/AssetsFileFormat/AssetsFile.cs"
grep -q 'public void Write(AssetsFileWriter writer' "$assets_dir/Standard/AssetsBundleFileFormat/AssetBundleFile.cs"
grep -q 'SetNewData(byte\[\] newBytes)' "$assets_dir/Standard/AssetsBundleFileFormat/AssetBundleDirectoryInfo.cs"

echo "AssetsTools.NET API smoke check passed"
