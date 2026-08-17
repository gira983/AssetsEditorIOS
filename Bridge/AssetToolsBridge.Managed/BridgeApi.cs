using AssetsTools.NET;
using AssetsTools.NET.Extra;
using System.Text.Json;

namespace AssetToolsBridge.Managed;

public sealed record BridgeAssetInfo(string FileName, long PathId, int ClassId, long ByteSize, string AssetType, string? Name);
public sealed record BridgeFileInfo(string Path, string Kind, int AssetCount, string? UnityVersion, uint FormatVersion, long FileSize, long MetadataSize, long DataOffset, uint? TargetPlatform, int? TypeCount, int? ExternalCount, bool? IsBigEndian);

public sealed class BridgeDocument : IDisposable
{
    private readonly AssetsManager manager;
    private readonly AssetsFileInstance? assetsFile;
    private readonly BundleFileInstance? bundleFile;

    private BridgeDocument(AssetsManager manager, AssetsFileInstance? assetsFile, BundleFileInstance? bundleFile)
    {
        this.manager = manager;
        this.assetsFile = assetsFile;
        this.bundleFile = bundleFile;
    }

    public static BridgeDocument Open(string path)
    {
        var manager = new AssetsManager { UseQuickLookup = true };
        try
        {
            if (IsBundle(path))
            {
                var bundle = manager.LoadBundleFile(path, true) ?? throw new InvalidDataException("AssetsTools.NET could not load the bundle.");
                return new BridgeDocument(manager, null, bundle);
            }

            var assets = manager.LoadAssetsFile(path, false) ?? throw new InvalidDataException("AssetsTools.NET could not load the SerializedFile.");
            return new BridgeDocument(manager, assets, null);
        }
        catch
        {
            manager.UnloadAll();
            throw;
        }
    }

    public BridgeFileInfo GetInfo()
    {
        if (assetsFile is not null)
        {
            var header = assetsFile.file.Header;
            return new BridgeFileInfo(assetsFile.path, "serializedFile", assetsFile.file.AssetInfos.Count, assetsFile.file.Metadata.UnityVersion, header.Version, header.FileSize, header.MetadataSize, header.DataOffset, assetsFile.file.Metadata.TargetPlatform, assetsFile.file.Metadata.TypeTreeTypes.Count, assetsFile.file.Metadata.Externals.Count, header.Endian);
        }

        if (bundleFile is not null)
        {
            var header = bundleFile.file.Header;
            return new BridgeFileInfo(bundleFile.path, "assetBundle", bundleFile.file.BlockAndDirInfo.DirectoryInfos.Count, header.EngineVersion, header.Version, new FileInfo(bundleFile.path).Length, 0, 0, null, null, null, null);
        }

        throw new InvalidOperationException("The document has no loaded file.");
    }

    public IReadOnlyList<BridgeAssetInfo> ListAssets()
    {
        if (assetsFile is not null)
        {
            return assetsFile.file.AssetInfos.Select(info =>
            {
                var classId = info.GetTypeId(assetsFile.file);
                return new BridgeAssetInfo(Path.GetFileName(assetsFile.path), info.PathId, classId, info.ByteSize, classId.ToString(), null);
            }).ToArray();
        }

        if (bundleFile is not null)
        {
            return bundleFile.file.BlockAndDirInfo.DirectoryInfos.Select(directory => new BridgeAssetInfo(directory.Name, 0, 0, directory.DecompressedSize, "bundleEntry", directory.Name)).ToArray();
        }

        return Array.Empty<BridgeAssetInfo>();
    }

    public void UpdateField(long pathId, string fieldPath, string value, string outputPath)
    {
        var file = RequireAssetsFile();
        var info = file.file.GetAssetInfo(pathId) ?? throw new KeyNotFoundException($"Asset path ID {pathId} was not found.");
        var field = manager.GetBaseField(file, info);
        if (field.IsDummy) throw new InvalidDataException("AssetsTools.NET returned a dummy base field.");
        var target = field[fieldPath];
        if (target.IsDummy) throw new KeyNotFoundException($"Field {fieldPath} was not found.");
        SetValue(target, value);
        info.SetNewData(field);
        WriteSerializedFile(file, outputPath);
    }

    public void ReadObject(long pathId)
    {
        var file = RequireAssetsFile();
        var info = file.file.GetAssetInfo(pathId) ?? throw new KeyNotFoundException($"Asset path ID {pathId} was not found.");
        var field = manager.GetBaseField(file, info);
        if (field.IsDummy) throw new InvalidDataException("AssetsTools.NET returned a dummy base field.");
    }

    public void WriteBundle(string outputPath)
    {
        if (bundleFile is null) throw new InvalidOperationException("The opened document is not an AssetBundle.");
        using var writer = new AssetsFileWriter(outputPath);
        bundleFile.file.Write(writer);
    }

    private AssetsFileInstance RequireAssetsFile() => assetsFile ?? throw new InvalidOperationException("The opened document is not a SerializedFile.");

    private static void SetValue(AssetTypeValueField field, string value)
    {
        switch (field.TemplateField.ValueType)
        {
            case AssetValueType.Bool: field.AsBool = ParseBool(value); break;
            case AssetValueType.Int8: field.AsSByte = sbyte.Parse(value, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.UInt8: field.AsByte = byte.Parse(value, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.Int16: field.AsShort = short.Parse(value, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.UInt16: field.AsUShort = ushort.Parse(value, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.Int32: field.AsInt = int.Parse(value, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.UInt32: field.AsUInt = uint.Parse(value, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.Int64: field.AsLong = long.Parse(value, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.UInt64: field.AsULong = ulong.Parse(value, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.Float: field.AsFloat = float.Parse(value, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.Double: field.AsDouble = double.Parse(value, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.String: field.AsString = value; break;
            default: throw new NotSupportedException($"Field type {field.TemplateField.Type} is not supported for editing.");
        }
    }

    private static bool ParseBool(string value) => value.Trim().ToLowerInvariant() switch
    {
        "true" or "1" => true,
        "false" or "0" => false,
        _ => throw new FormatException($"Invalid boolean value: {value}")
    };

    private static void WriteSerializedFile(AssetsFileInstance file, string outputPath)
    {
        using var writer = new AssetsFileWriter(outputPath);
        file.file.Write(writer);
    }

    private static bool IsBundle(string path)
    {
        using var stream = File.OpenRead(path);
        Span<byte> magic = stackalloc byte[7];
        var read = stream.Read(magic);
        return read == 7 && (magic.SequenceEqual("UnityFS"u8) || magic.SequenceEqual("UnityRaw"u8) || magic.SequenceEqual("UnityWeb"u8));
    }
}

public static class BridgeApi
{
    private static readonly JsonSerializerOptions Options = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    public static string Execute(string requestJson)
    {
        using var document = JsonDocument.Parse(requestJson);
        var root = document.RootElement;
        var operation = root.GetProperty("operation").GetString() ?? throw new FormatException("Missing operation.");
        var path = root.GetProperty("path").GetString() ?? throw new FormatException("Missing path.");
        using var file = BridgeDocument.Open(path);
        switch (operation)
        {
            case "inspect":
                return JsonSerializer.Serialize(new { info = file.GetInfo(), assets = file.ListAssets() }, Options);
            case "readObject":
                file.ReadObject(root.GetProperty("pathId").GetInt64());
                return JsonSerializer.Serialize(new { ok = true }, Options);
            case "updateField":
                file.UpdateField(root.GetProperty("pathId").GetInt64(), root.GetProperty("fieldPath").GetString() ?? throw new FormatException("Missing fieldPath."), root.GetProperty("value").GetString() ?? throw new FormatException("Missing value."), root.GetProperty("outputPath").GetString() ?? throw new FormatException("Missing outputPath."));
                return JsonSerializer.Serialize(new { ok = true }, Options);
            case "writeBundle":
                file.WriteBundle(root.GetProperty("outputPath").GetString() ?? throw new FormatException("Missing outputPath."));
                return JsonSerializer.Serialize(new { ok = true }, Options);
            default: throw new NotSupportedException($"Unknown operation: {operation}");
        }
    }

    public static string Failure(string message) => JsonSerializer.Serialize(new { error = message }, Options);

    public static string Inspect(string path) => Execute(JsonSerializer.Serialize(new { operation = "inspect", path }));
}
