using AssetsTools.NET;
using AssetsTools.NET.Extra;
using System.Text.Json;

namespace AssetToolsBridge.Managed;

public sealed record BridgeAssetInfo(
    string FileName,
    long PathId,
    int ClassId,
    long ByteSize,
    string AssetType,
    string? Name);

public sealed record BridgeDocumentInfo(
    string Path,
    string Kind,
    int AssetCount,
    string? UnityVersion);

public sealed record BridgeObjectInfo(
    string FileName,
    long PathId,
    int ClassId,
    long ByteSize,
    string AssetType,
    string? Name);

public sealed record BridgeFieldInfo(
    string Path,
    string Name,
    string Type,
    string Value,
    int Depth,
    bool Editable);

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
        var manager = new AssetsManager();
        try
        {
            if (IsBundle(path))
            {
                var bundle = manager.LoadBundleFile(path, true) ?? throw new InvalidDataException("AssetsTools.NET could not load the bundle.");
                return new BridgeDocument(manager, null, bundle);
            }

            var assets = manager.LoadAssetsFile(path, false) ?? throw new InvalidDataException("AssetsTools.NET could not load the serialized file.");
            return new BridgeDocument(manager, assets, null);
        }
        catch
        {
            manager.UnloadAll();
            throw;
        }
    }

    public BridgeDocumentInfo GetInfo()
    {
        if (assetsFile is not null)
        {
            return new BridgeDocumentInfo(
                assetsFile.path,
                "serializedFile",
                assetsFile.file.AssetInfos.Count,
                assetsFile.file.Metadata.UnityVersion);
        }

        if (bundleFile is not null)
        {
            return new BridgeDocumentInfo(
                bundleFile.path,
                "assetBundle",
                bundleFile.file.BlockAndDirInfo.DirectoryInfos.Count,
                bundleFile.file.Header?.EngineVersion);
        }

        throw new InvalidOperationException("The document has no loaded file.");
    }

    public IReadOnlyList<BridgeAssetInfo> ListAssets()
    {
        if (assetsFile is not null)
        {
            return assetsFile.file.AssetInfos
                .Select(info => new BridgeAssetInfo(
                    Path.GetFileName(assetsFile.path),
                    info.PathId,
                    info.GetAbsoluteByteOffset(assetsFile.file.Header),
                    info.ByteSize,
                    info.GetTypeId(assetsFile.file),
                    info.GetTypeId(assetsFile.file).ToString(),
                    null))
                .ToArray();
        }

        if (bundleFile is not null)
        {
            return bundleFile.file.BlockAndDirInfo.DirectoryInfos
                .Select(directory => new BridgeAssetInfo(
                    directory.Name,
                    0,
                    0,
                    directory.DecompressedSize,
                    "bundleEntry",
                    directory.Name))
                .ToArray();
        }

        return Array.Empty<BridgeAssetInfo>();
    }

    public IReadOnlyList<BridgeObjectInfo> ListObjects()
    {
        if (assetsFile is null)
            return Array.Empty<BridgeObjectInfo>();

        return assetsFile.file.AssetInfos
            .Select(info => new BridgeObjectInfo(
                Path.GetFileName(assetsFile.path),
                info.PathId,
                info.GetTypeId(assetsFile.file),
                info.ByteSize,
                info.GetTypeId(assetsFile.file).ToString(),
                null))
            .ToArray();
    }

    public IReadOnlyList<BridgeFieldInfo> ListFields(long pathId)
    {
        if (assetsFile is null)
            throw new InvalidOperationException("Fields are available for SerializedFiles, not bundle directory entries.");

        var info = assetsFile.file.GetAssetInfo(pathId) ?? throw new InvalidDataException($"Asset with path ID {pathId} was not found.");
        var root = manager.GetBaseField(assetsFile, info);
        var fields = new List<BridgeFieldInfo>();
        Flatten(root, root.FieldName, 0, fields);
        return fields;
    }

    public void UpdateField(long pathId, string fieldPath, string value)
    {
        if (assetsFile is null)
            throw new InvalidOperationException("Fields are available for SerializedFiles, not bundle directory entries.");

        var info = assetsFile.file.GetAssetInfo(pathId) ?? throw new InvalidDataException($"Asset with path ID {pathId} was not found.");
        var root = manager.GetBaseField(assetsFile, info);
        var field = root[fieldPath] ?? throw new InvalidDataException($"Field {fieldPath} was not found.");
        if (field.IsDummy)
            throw new InvalidDataException($"Field {fieldPath} was not found.");

        SetValue(field, value);
        info.SetNewData(root.WriteToByteArray(assetsFile.file.Header.EndianType == 1));
    }

    public void Write(string outputPath)
    {
        if (assetsFile is not null)
        {
            using var writer = new AssetsFileWriter(outputPath);
            assetsFile.file.Write(writer);
            return;
        }

        if (bundleFile is not null)
        {
            using var writer = new AssetsFileWriter(outputPath);
            bundleFile.file.Write(writer);
            return;
        }

        throw new InvalidOperationException("The document has no loaded file.");
    }

    public void Dispose() => manager.UnloadAll();

    private static void Flatten(AssetTypeValueField field, string path, int depth, ICollection<BridgeFieldInfo> result)
    {
        if (result.Count >= 10_000)
            return;

        var type = field.TypeName;
        var editable = field.Children.Count == 0 && field.Value is not null;
        result.Add(new BridgeFieldInfo(path, field.FieldName, type, ValueAsString(field), depth, editable));
        for (var index = 0; index < field.Children.Count; index++)
        {
            var child = field.Children[index];
            var childPath = $"{path}.{child.FieldName}";
            Flatten(child, childPath, depth + 1, result);
        }
    }

    private static string ValueAsString(AssetTypeValueField field)
    {
        if (field.Value is null)
            return string.Empty;

        return field.TemplateField.ValueType switch
        {
            AssetValueType.Bool => field.AsBool.ToString().ToLowerInvariant(),
            AssetValueType.Int8 => field.AsSByte.ToString(),
            AssetValueType.UInt8 => field.AsByte.ToString(),
            AssetValueType.Int16 => field.AsShort.ToString(),
            AssetValueType.UInt16 => field.AsUShort.ToString(),
            AssetValueType.Int32 => field.AsInt.ToString(),
            AssetValueType.UInt32 => field.AsUInt.ToString(),
            AssetValueType.Int64 => field.AsLong.ToString(),
            AssetValueType.UInt64 => field.AsULong.ToString(),
            AssetValueType.Float => field.AsFloat.ToString(System.Globalization.CultureInfo.InvariantCulture),
            AssetValueType.Double => field.AsDouble.ToString(System.Globalization.CultureInfo.InvariantCulture),
            AssetValueType.String => field.AsString,
            _ => string.Empty
        };
    }

    private static void SetValue(AssetTypeValueField field, string value)
    {
        var type = field.TemplateField.ValueType;
        var trimmed = value.Trim();
        switch (type)
        {
            case AssetValueType.Bool:
                if (!bool.TryParse(trimmed, out var boolValue) && trimmed is not ("0" or "1")) throw new FormatException("Expected true, false, 0, or 1.");
                field.AsBool = boolValue || trimmed == "1";
                break;
            case AssetValueType.Int8: field.AsSByte = sbyte.Parse(trimmed, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.UInt8: field.AsByte = byte.Parse(trimmed, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.Int16: field.AsShort = short.Parse(trimmed, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.UInt16: field.AsUShort = ushort.Parse(trimmed, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.Int32: field.AsInt = int.Parse(trimmed, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.UInt32: field.AsUInt = uint.Parse(trimmed, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.Int64: field.AsLong = long.Parse(trimmed, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.UInt64: field.AsULong = ulong.Parse(trimmed, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.Float: field.AsFloat = float.Parse(trimmed, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.Double: field.AsDouble = double.Parse(trimmed, System.Globalization.CultureInfo.InvariantCulture); break;
            case AssetValueType.String: field.AsString = value; break;
            default: throw new NotSupportedException($"Field type {field.TypeName} is not editable.");
        }
    }

    private static bool IsBundle(string path)
    {
        using var stream = File.OpenRead(path);
        Span<byte> magic = stackalloc byte[7];
        var read = stream.Read(magic);
        return read == 7 &&
            (magic.SequenceEqual("UnityFS"u8) || magic.SequenceEqual("UnityRaw"u8) || magic.SequenceEqual("UnityWeb"u8));
    }
}

public static class BridgeApi
{
    private sealed record BridgeRequest(string Operation, string Path, string? OutputPath, long? PathId, string? FieldPath, string? Value);

    public static string Execute(string requestJson)
    {
        var request = JsonSerializer.Deserialize<BridgeRequest>(requestJson, JsonOptions) ?? throw new InvalidDataException("Invalid bridge request.");
        using var document = BridgeDocument.Open(request.Path);
        return request.Operation switch
        {
            "inspect" => JsonSerializer.Serialize(new { info = document.GetInfo(), assets = document.ListAssets() }, JsonOptions),
            "listObjects" => JsonSerializer.Serialize(document.ListObjects(), JsonOptions),
            "listFields" when request.PathId is long pathId => JsonSerializer.Serialize(document.ListFields(pathId), JsonOptions),
            "updateField" when request.PathId is long pathId && request.FieldPath is not null && request.Value is not null => UpdateAndWrite(document, pathId, request.FieldPath, request.Value, request.OutputPath),
            _ => throw new InvalidDataException("Unsupported bridge operation.")
        };
    }

    public static string Error(string message) => JsonSerializer.Serialize(new { error = message }, JsonOptions);

    private static string UpdateAndWrite(BridgeDocument document, long pathId, string fieldPath, string value, string? outputPath)
    {
        if (string.IsNullOrWhiteSpace(outputPath))
            throw new InvalidDataException("outputPath is required for updateField.");
        document.UpdateField(pathId, fieldPath, value);
        document.Write(outputPath);
        return JsonSerializer.Serialize(new { ok = true, outputPath }, JsonOptions);
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true
    };
}
