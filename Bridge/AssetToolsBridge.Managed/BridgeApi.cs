using AssetsTools.NET;
using AssetsTools.NET.Extra;
using System.Text.Json;

namespace AssetToolsBridge.Managed;

public sealed record BridgeAssetInfo(string FileName, long PathId, int ClassId, long ByteSize, string AssetType, string? Name);
public sealed record BridgeDocumentInfo(string Path, string Kind, int AssetCount, string? UnityVersion);
public sealed record BridgeResponse(BridgeDocumentInfo? Info, IReadOnlyList<BridgeAssetInfo> Assets, string? Error);

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
                var bundle = manager.LoadBundleFile(path, true);
                if (bundle is null) throw new InvalidDataException("AssetsTools.NET could not load the AssetBundle.");
                return new BridgeDocument(manager, null, bundle);
            }

            var assets = manager.LoadAssetsFile(path, false);
            if (assets is null) throw new InvalidDataException("AssetsTools.NET could not load the SerializedFile.");
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
            return new BridgeDocumentInfo(assetsFile.path, "serializedFile", assetsFile.file.AssetInfos.Count, assetsFile.file.Metadata.UnityVersion);
        }

        if (bundleFile is not null)
        {
            return new BridgeDocumentInfo(bundleFile.path, "assetBundle", bundleFile.file.BlockAndDirInfo.DirectoryInfos.Count, bundleFile.file.Header?.EngineVersion);
        }

        throw new InvalidOperationException("The document has no loaded file.");
    }

    public IReadOnlyList<BridgeAssetInfo> ListAssets()
    {
        if (assetsFile is not null)
        {
            return assetsFile.file.AssetInfos.Select(info => new BridgeAssetInfo(
                Path.GetFileName(assetsFile.path),
                info.PathId,
                info.GetTypeId(assetsFile.file),
                info.ByteSize,
                UnityTypeName(info.GetTypeId(assetsFile.file)),
                TryReadName(info))).ToArray();
        }

        if (bundleFile is not null)
        {
            return bundleFile.file.BlockAndDirInfo.DirectoryInfos.Select(directory => new BridgeAssetInfo(
                directory.Name,
                0,
                0,
                directory.DecompressedSize,
                "bundleEntry",
                directory.Name)).ToArray();
        }

        return Array.Empty<BridgeAssetInfo>();
    }

    public BridgeResponse ReadObject(long pathId)
    {
        if (assetsFile is null) throw new InvalidOperationException("Object reads require a SerializedFile.");
        var info = assetsFile.file.GetAssetInfo(pathId);
        if (info is null) throw new KeyNotFoundException($"Asset path ID {pathId} was not found.");
        var field = manager.GetBaseField(assetsFile, info);
        return new BridgeResponse(GetInfo(), new[] { new BridgeAssetInfo(
            Path.GetFileName(assetsFile.path), info.PathId, info.GetTypeId(assetsFile.file), info.ByteSize,
            UnityTypeName(info.GetTypeId(assetsFile.file)), field["m_Name"].IsDummy ? null : field["m_Name"].AsString) }, null);
    }

    public void UpdateField(long pathId, string fieldPath, string value, string outputPath)
    {
        if (assetsFile is null) throw new InvalidOperationException("Object edits require a SerializedFile.");
        if (string.IsNullOrWhiteSpace(fieldPath)) throw new ArgumentException("fieldPath is required.", nameof(fieldPath));
        var info = assetsFile.file.GetAssetInfo(pathId) ?? throw new KeyNotFoundException($"Asset path ID {pathId} was not found.");
        var field = manager.GetBaseField(assetsFile, info);
        var target = field[fieldPath];
        if (target.IsDummy) throw new KeyNotFoundException($"Field '{fieldPath}' was not found.");
        ApplyValue(target, value);
        info.SetNewData(field);
        WriteSerializedFile(outputPath);
    }

    public void WriteSerializedFile(string outputPath)
    {
        if (assetsFile is null) throw new InvalidOperationException("SerializedFile output requires a SerializedFile.");
        using var writer = new AssetsFileWriter(outputPath);
        assetsFile.file.Write(writer);
    }

    public void WriteBundle(string outputPath)
    {
        if (bundleFile is null) throw new InvalidOperationException("AssetBundle output requires an AssetBundle.");
        using var writer = new AssetsFileWriter(outputPath);
        bundleFile.file.Write(writer);
    }

    public void Dispose() => manager.UnloadAll();

    private static void ApplyValue(AssetTypeValueField field, string text)
    {
        var value = text.Trim();
        switch (field.TemplateField.ValueType)
        {
            case AssetValueType.Bool: field.AsBool = Parse(value, bool.TryParse, "bool"); break;
            case AssetValueType.Int8: field.AsSByte = Parse(value, sbyte.TryParse, "SInt8"); break;
            case AssetValueType.UInt8: field.AsByte = Parse(value, byte.TryParse, "UInt8"); break;
            case AssetValueType.Int16: field.AsShort = Parse(value, short.TryParse, "SInt16"); break;
            case AssetValueType.UInt16: field.AsUShort = Parse(value, ushort.TryParse, "UInt16"); break;
            case AssetValueType.Int32: field.AsInt = Parse(value, int.TryParse, "SInt32"); break;
            case AssetValueType.UInt32: field.AsUInt = Parse(value, uint.TryParse, "UInt32"); break;
            case AssetValueType.Int64: field.AsLong = Parse(value, long.TryParse, "SInt64"); break;
            case AssetValueType.UInt64: field.AsULong = Parse(value, ulong.TryParse, "UInt64"); break;
            case AssetValueType.Float: field.AsFloat = Parse(value, float.TryParse, "float"); break;
            case AssetValueType.Double: field.AsDouble = Parse(value, double.TryParse, "double"); break;
            case AssetValueType.String: field.AsString = value; break;
            default: throw new NotSupportedException($"Field type '{field.TemplateField.Type}' is not editable by the bridge.");
        }
    }

    private static T Parse<T>(string value, TryParse<T> parser, string type) where T : struct
    {
        if (!parser(value, out var result)) throw new FormatException($"'{value}' is not a valid {type}.");
        return result;
    }

    private delegate bool TryParse<T>(string value, out T result) where T : struct;

    private string? TryReadName(AssetFileInfo info)
    {
        try
        {
            var field = manager.GetBaseField(assetsFile!, info);
            var name = field["m_Name"];
            return name.IsDummy ? null : name.AsString;
        }
        catch
        {
            return null;
        }
    }

    private static bool IsBundle(string path)
    {
        using var stream = File.OpenRead(path);
        Span<byte> magic = stackalloc byte[7];
        var read = stream.Read(magic);
        return read == 7 && (magic.SequenceEqual("UnityFS"u8) || magic.SequenceEqual("UnityRaw"u8) || magic.SequenceEqual("UnityWeb"u8));
    }

    private static string UnityTypeName(int typeId) => typeId switch
    {
        1 => "GameObject", 28 => "Texture2D", 43 => "Mesh", 48 => "Shader", 49 => "TextAsset", 83 => "AudioClip", 114 => "MonoBehaviour", 115 => "MonoScript", 128 => "Font", _ => $"Class {typeId}"
    };
}

public static class BridgeApi
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public static string Execute(string requestJson)
    {
        try
        {
            var request = JsonSerializer.Deserialize<BridgeRequest>(requestJson, JsonOptions) ?? throw new InvalidDataException("Invalid bridge request.");
            using var document = BridgeDocument.Open(request.Path);
            switch (request.Operation)
            {
                case "inspect": return Serialize(new BridgeResponse(document.GetInfo(), document.ListAssets(), null));
                case "readObject": return Serialize(document.ReadObject(request.PathId ?? throw new InvalidDataException("pathId is required.")));
                case "updateField":
                    if (request.OutputPath is null || request.FieldPath is null || request.Value is null || request.PathId is null) throw new InvalidDataException("updateField requires outputPath, pathId, fieldPath, and value.");
                    document.UpdateField(request.PathId.Value, request.FieldPath, request.Value, request.OutputPath);
                    return Serialize(new BridgeResponse(document.GetInfo(), Array.Empty<BridgeAssetInfo>(), null));
                case "writeBundle":
                    if (request.OutputPath is null) throw new InvalidDataException("writeBundle requires outputPath.");
                    document.WriteBundle(request.OutputPath);
                    return Serialize(new BridgeResponse(document.GetInfo(), Array.Empty<BridgeAssetInfo>(), null));
                default: throw new InvalidDataException($"Unknown bridge operation '{request.Operation}'.");
            }
        }
        catch (Exception exception)
        {
            return Serialize(new BridgeResponse(null, Array.Empty<BridgeAssetInfo>(), exception.Message));
        }
    }

    private static string Serialize(BridgeResponse response) => JsonSerializer.Serialize(response, JsonOptions);
}

public sealed record BridgeRequest(string Operation, string Path, string? OutputPath, long? PathId, string? FieldPath, string? Value);
