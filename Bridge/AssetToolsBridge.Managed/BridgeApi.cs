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
                var bundle = manager.LoadBundleFile(path, true);
                if (bundle is null)
                    throw new InvalidDataException("AssetsTools.NET could not load the bundle.");
                return new BridgeDocument(manager, null, bundle);
            }

            var assets = manager.LoadAssetsFile(path, false);
            if (assets is null)
                throw new InvalidDataException("AssetsTools.NET could not load the serialized file.");
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
                    directory.DecompressedSize,
                    0,
                    "bundleEntry",
                    directory.Name))
                .ToArray();
        }

        return Array.Empty<BridgeAssetInfo>();
    }

    public string ReadObject(long pathId)
    {
        if (assetsFile is null)
            throw new InvalidOperationException("Object reads require a SerializedFile.");

        var info = assetsFile.file.GetAssetInfo(pathId);
        if (info is null)
            throw new KeyNotFoundException($"Asset path ID {pathId} was not found.");

        var field = manager.GetBaseField(assetsFile, info);
        return JsonSerializer.Serialize(ToJson(field));
    }

    public void WriteObject(long pathId, string fieldPath, JsonElement value, string outputPath)
    {
        if (assetsFile is null)
            throw new InvalidOperationException("Object writes require a SerializedFile.");

        var info = assetsFile.file.GetAssetInfo(pathId);
        if (info is null)
            throw new KeyNotFoundException($"Asset path ID {pathId} was not found.");

        var field = manager.GetBaseField(assetsFile, info);
        var target = FindField(field, fieldPath);
        SetFieldValue(target, value);
        info.SetNewData(field);

        using var writer = new AssetsFileWriter(outputPath);
        assetsFile.file.Write(writer);
    }

    public void Dispose() => manager.UnloadAll();

    private static object ToJson(AssetTypeValueField field)
    {
        if (field.Children.Count == 0)
            return field.AsString;

        var result = new Dictionary<string, object?>();
        foreach (var child in field.Children)
            result[child.FieldName] = ToJson(child);
        return result;
    }

    private static AssetTypeValueField FindField(AssetTypeValueField root, string path)
    {
        var current = root;
        foreach (var segment in path.Split('.', StringSplitOptions.RemoveEmptyEntries))
        {
            current = current[segment];
            if (current.IsDummy)
                throw new KeyNotFoundException($"Field {path} was not found.");
        }
        return current;
    }

    private static void SetFieldValue(AssetTypeValueField field, JsonElement value)
    {
        switch (field.TemplateField.ValueType)
        {
            case AssetValueType.String:
                field.AsString = value.GetString() ?? string.Empty;
                return;
            case AssetValueType.Bool:
                field.AsBool = value.GetBoolean();
                return;
            case AssetValueType.Int8:
                field.AsSByte = value.GetSByte();
                return;
            case AssetValueType.UInt8:
                field.AsByte = value.GetByte();
                return;
            case AssetValueType.Int16:
                field.AsShort = value.GetInt16();
                return;
            case AssetValueType.UInt16:
                field.AsUShort = value.GetUInt16();
                return;
            case AssetValueType.Int32:
                field.AsInt = value.GetInt32();
                return;
            case AssetValueType.UInt32:
                field.AsUInt = value.GetUInt32();
                return;
            case AssetValueType.Int64:
                field.AsLong = value.GetInt64();
                return;
            case AssetValueType.UInt64:
                field.AsULong = value.GetUInt64();
                return;
            case AssetValueType.Float:
                field.AsFloat = value.GetSingle();
                return;
            case AssetValueType.Double:
                field.AsDouble = value.GetDouble();
                return;
            default:
                throw new NotSupportedException($"Field type {field.TemplateField.Type} is not supported for editing.");
        }
    }

    private static bool IsBundle(string path)
    {
        using var stream = File.OpenRead(path);
        Span<byte> magic = stackalloc byte[7];
        var read = stream.Read(magic);
        return read == 7 &&
            (magic.SequenceEqual("UnityFS"u8) ||
             magic.SequenceEqual("UnityRaw"u8) ||
             magic.SequenceEqual("UnityWeb"u8));
    }
}

public static class BridgeApi
{
    public static string Execute(string request)
    {
        var command = JsonSerializer.Deserialize<BridgeRequest>(request)
            ?? throw new InvalidDataException("The bridge request is empty.");

        using var document = BridgeDocument.Open(command.Path);
        return command.Operation switch
        {
            "inspect" => JsonSerializer.Serialize(new { info = document.GetInfo(), assets = document.ListAssets() }, JsonOptions),
            "readObject" => JsonSerializer.Serialize(new { objectData = JsonSerializer.Deserialize<JsonElement>(document.ReadObject(command.PathId)) }, JsonOptions),
            _ => throw new NotSupportedException($"Unknown bridge operation: {command.Operation}")
        };
    }

    public static string Error(string message) => JsonSerializer.Serialize(new { error = message }, JsonOptions);

    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    private sealed record BridgeRequest(string Operation, string Path, long PathId, string? FieldPath, JsonElement Value, string? OutputPath);
}
