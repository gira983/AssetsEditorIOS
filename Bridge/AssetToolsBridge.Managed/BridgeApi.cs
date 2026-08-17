using AssetsTools.NET;
using AssetsTools.NET.Extra;
using System.Globalization;
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
            return assetsFile.file.AssetInfos.Select(info =>
            {
                var classId = info.GetTypeId(assetsFile.file);
                return new BridgeAssetInfo(Path.GetFileName(assetsFile.path), info.PathId, classId, info.ByteSize, UnityTypeName(classId), TryReadName(info));
            }).ToArray();
        }

        if (bundleFile is not null)
        {
            return bundleFile.file.BlockAndDirInfo.DirectoryInfos.Select(directory => new BridgeAssetInfo(
                directory.Name, 0, 0, directory.DecompressedSize, "bundleEntry", directory.Name)).ToArray();
        }

        return Array.Empty<BridgeAssetInfo>();
    }

    public BridgeResponse ReadObject(long pathId)
    {
        if (assetsFile is null) throw new InvalidOperationException("Object reads require a SerializedFile.");
        var info = assetsFile.file.GetAssetInfo(pathId) ?? throw new KeyNotFoundException($"Asset path ID {pathId} was not found.");
        var field = manager.GetBaseField(assetsFile, info);
        var classId = info.GetTypeId(assetsFile.file);
        var name = field["m_Name"];
        return new BridgeResponse(GetInfo(), new[] { new BridgeAssetInfo(Path.GetFileName(assetsFile.path), info.PathId, classId, info.ByteSize, UnityTypeName(classId), name.IsDummy ? null : name.AsString) }, null);
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
        var culture = CultureInfo.InvariantCulture;
        switch (field.TemplateField.ValueType)
        {
            case AssetValueType.Bool: field.AsBool = bool.Parse(value); break;
            case AssetValueType.Int8: field.AsSByte = sbyte.Parse(value, culture); break;
            case AssetValueType.UInt8: field.AsByte = byte.Parse(value, culture); break;
            case AssetValueType.Int16: field.AsShort = short.Parse(value, culture); break;
            case AssetValueType.UInt16: field.AsUShort = ushort.Parse(value, culture); break;
            case AssetValueType.Int32: field.AsInt = int.Parse(value, culture); break;
            case AssetValueType.UInt32: field.AsUInt = uint.Parse(value, culture); break;
            case AssetValueType.Int64: field.AsLong = long.Parse(value, culture); break;
            case AssetValueType.UInt64: field.AsULong = ulong.Parse(value, culture); break;
            case AssetValueType.Float: field.AsFloat = float.Parse(value, culture); break;
            case AssetValueType.Double: field.AsDouble = double.Parse(value, culture); break;
            case AssetValueType.String: field.AsString = value; break;
            default: throw new NotSupportedException($"Field type '{field.TemplateField.Type}' is not editable by the bridge.");
        }
    }

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
            return request.Operation switch
            {
                "inspect" => Serialize(new BridgeResponse(document.GetInfo(), document.ListAssets(), null)),
                "readObject" => Serialize(document.ReadObject(request.PathId ?? throw new InvalidDataException("pathId is required."))),
                "updateField" => ExecuteUpdate(document, request),
                "writeBundle" => ExecuteWriteBundle(document, request),
                _ => throw new InvalidDataException($"Unknown bridge operation '{request.Operation}'.")
            };
        }
        catch (Exception exception)
        {
            return Failure(exception.Message);
        }
    }

    public static string Failure(string message) => Serialize(new BridgeResponse(null, Array.Empty<BridgeAssetInfo>(), message));

    private static string ExecuteUpdate(BridgeDocument document, BridgeRequest request)
    {
        if (request.OutputPath is null || request.FieldPath is null || request.Value is null || request.PathId is null)
            throw new InvalidDataException("updateField requires outputPath, pathId, fieldPath, and value.");
        document.UpdateField(request.PathId.Value, request.FieldPath, request.Value, request.OutputPath);
        return Serialize(new BridgeResponse(document.GetInfo(), Array.Empty<BridgeAssetInfo>(), null));
    }

    private static string ExecuteWriteBundle(BridgeDocument document, BridgeRequest request)
    {
        if (request.OutputPath is null) throw new InvalidDataException("writeBundle requires outputPath.");
        document.WriteBundle(request.OutputPath);
        return Serialize(new BridgeResponse(document.GetInfo(), Array.Empty<BridgeAssetInfo>(), null));
    }

    private static string Serialize(BridgeResponse response) => JsonSerializer.Serialize(response, JsonOptions);
}

public sealed record BridgeRequest(string Operation, string Path, string? OutputPath, long? PathId, string? FieldPath, string? Value);
