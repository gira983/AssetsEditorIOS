#!/usr/bin/env bash
set -euo pipefail

repo="https://raw.githubusercontent.com/nesrak1/AssetsTools.NET/v24"
work_dir="${RUNNER_TEMP:-/tmp}/assetstools-api"
mkdir -p "$work_dir"

for path in \
  AssetTools.NET/Extra/AssetsManager/AssetsManager.cs \
  AssetTools.NET/Extra/AssetsManager/AssetsManager.Assets.cs \
  AssetTools.NET/Extra/AssetsManager/AssetsManager.Bundle.cs \
  AssetTools.NET/Extra/AssetsManager/AssetsManager.Deserialization.cs \
  AssetTools.NET/Standard/AssetsFileFormat/AssetsFile.cs \
  AssetTools.NET/Standard/AssetsFileFormat/AssetFileInfo.cs \
  AssetTools.NET/Standard/AssetTypeClass/AssetTypeValueField.cs \
  AssetTools.NET/Standard/AssetsBundleFileFormat/AssetBundleFile.cs \
  AssetTools.NET/Standard/AssetsBundleFileFormat/AssetBundleDirectoryInfo.cs
 do
  curl --fail --silent --show-error "$repo/$path" -o "$work_dir/$(basename "$path")"
 done

grep -q 'LoadAssetsFile(string path' "$work_dir/AssetsManager.Assets.cs"
grep -q 'LoadBundleFile(string path' "$work_dir/AssetsManager.Bundle.cs"
grep -q 'GetBaseField(AssetsFileInstance inst, AssetFileInfo info' "$work_dir/AssetsManager.Deserialization.cs"
grep -q 'WriteToByteArray' "$work_dir/AssetTypeValueField.cs"
grep -q 'SetNewData(byte\[\])' "$work_dir/AssetFileInfo.cs" || grep -q 'SetNewData(byte\[\] newBytes)' "$work_dir/AssetFileInfo.cs"
grep -q 'public void Write(AssetsFileWriter writer' "$work_dir/AssetsFile.cs"
grep -q 'public void Write(AssetsFileWriter writer' "$work_dir/AssetBundleFile.cs"
grep -q 'SetNewData(byte\[\] newBytes)' "$work_dir/AssetBundleDirectoryInfo.cs"

echo "AssetsTools.NET v24 API smoke check passed"
