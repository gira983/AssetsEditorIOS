using AssetsTools.NET;
using AssetsTools.NET.Extra;
using System.Text.Json;

namespace AssetToolsBridge.Managed;

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
        if (!File.Exists(path))
            throw new FileNotFoundException("Input file was not found.", path);
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

    public object Inspect()
    {
        if (assetsFile is not null)
        {
            return new
            {
                info = new { path = assetsFile.path, kind = "serializedFile", assetCount = assetsFile.file.AssetInfos.Count, unityVersion = assetsFile.file.Metadata.UnityVersion },
                assets = assetsFile.file.AssetInfos.Select(info => new { fileName = Path.GetFileName(assetsFile.path), pathId = info.PathId, classId = info.GetTypeId(assetsFile.file), byteSize = info.ByteSize, assetType = info.GetTypeId(assetsFile.file).ToString(), name = (string?)null })
            };
        }
        if (bundleFile is not null)
        {
            return new
            {
                info = new { path = bundleFile.path, kind = "assetBundle", assetCount = bundleFile.file.BlockAndDirInfo.DirectoryInfos.Count, unityVersion = bundleFile.file.Header.EngineVersion },
                assets = bundleFile.file.BlockAndDirInfo.DirectoryInfos.Select(directory => new { fileName = directory.Name, pathId = 0L, classId = 0, byteSize = (long)directory.DecompressedSize, assetType = "bundleEntry", name = directory.Name })
            };
        }
        throw new InvalidOperationException("The document has no loaded file.");
    }

    public object ListObjects()
    {
        if (assetsFile is null)
            return new { objects = Array.Empty<object>() };
        return new
        {
            objects = assetsFile.file.AssetInfos.Select(info => new { id = $"{info.PathId}:{info.GetTypeId(assetsFile.file)}", pathID = info.PathId, typeID = info.GetTypeId(assetsFile.file), byteOffset = (ulong)info.GetAbsoluteByteOffset(assetsFile.file.Header), byteSize = (ulong)info.ByteSize, typeName = info.GetTypeId(assetsFile.file).ToString(), displayName = $"{info.GetTypeId(assetsFile.file)} • {info.PathId}" }).ToArray()
        };
    }

    public object GetFields(long pathId)
    {
        if (assetsFile is null)
            throw new InvalidOperationException("Fields are available only for serialized files.");
        var info = assetsFile.file.GetAssetInfo(pathId) ?? throw new KeyNotFoundException($"Asset {pathId} was not found.");
        var field = manager.GetBaseField(assetsFile, info);
        var fields = new List<object>();
        Flatten(field, field.FieldName, 0, fields);
        return new { fields = fields.ToArray() };
    }

    public void UpdateField(long pathId, string fieldPath, string value, string outputPath)
    {
        if (assetsFile is null)
            throw new InvalidOperationException("Field updates are available only for serialized files.");
        var info = assetsFile.file.GetAssetInfo(pathId) ?? throw new KeyNotFoundException($"Asset {pathId} was not found.");
        var field = manager.GetBaseField(assetsFile, info);
        var target = field[fieldPath];
        if (target.IsDummy)
            throw new KeyNotFoundException($"Field {fieldPath} was not found.");
        SetValue(target, value);
        info.SetNewData(field);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outputPath))!);
        using var writer = new AssetsFileWriter(outputPath);
        assetsFile.file.Write(writer);
    }

    public void WriteBundle(string outputPath)
    {
        if (bundleFile is null)
            throw new InvalidOperationException("The opened document is not an AssetBundle.");
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outputPath))!);
        using var writer = new AssetsFileWriter(outputPath);
        bundleFile.file.Write(writer);
    }

    public void Dispose() => manager.UnloadAll();

    private static void Flatten(AssetTypeValueField field, string path, int depth, List<object> result)
    {
        if (field.Children.Count == 0)
        {
            result.Add(new { id = path, name = path, type = field.TypeName, value = field.AsString, depth, editable = field.TemplateField.HasValue });
            return;
        }
        foreach (var child in field.Children)
            Flatten(child, $"{path}.{child.FieldName}", depth + 1, result);
    }

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
            default: throw new NotSupportedException($"Field type {field.TypeName} is not editable.");
        }
    }

    private static bool ParseBool(string value) => value.Trim().ToLowerInvariant() switch
    {
        "true" or "1" => true,
        "false" or "0" => false,
        _ => throw new FormatException($"Invalid boolean value: {value}")
    };

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
    public static string Execute(string request)
    {
        using var document = JsonDocument.Parse(request);
        var root = document.RootElement;
        var operation = root.GetProperty("operation").GetString() ?? throw new InvalidDataException("Missing operation.");
        var path = root.GetProperty("path").GetString() ?? throw new InvalidDataException("Missing path.");
        using var opened = BridgeDocument.Open(path);
        object result = operation switch
        {
            "inspect" => opened.Inspect(),
            "listObjects" => opened.ListObjects(),
            "getFields" => opened.GetFields(root.GetProperty("pathId").GetInt64()),
            "updateField" => Update(opened, root),
            "writeBundle" => WriteBundle(opened, root),
            _ => throw new NotSupportedException($"Unknown operation: {operation}")
        };
        return JsonSerializer.Serialize(new { ok = true, result }, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
    }

    public static string Error(string message) => JsonSerializer.Serialize(new { ok = false, error = message });
    public static string Inspect(string path) => Execute(JsonSerializer.Serialize(new { operation = "inspect", path }));

    private static object Update(BridgeDocument document, JsonElement root)
    {
        document.UpdateField(root.GetProperty("pathId").GetInt64(), root.GetProperty("fieldPath").GetString()!, root.GetProperty("value").GetString()!, root.GetProperty("outputPath").GetString()!);
        return new { written = true };
    }

    private static object WriteBundle(BridgeDocument document, JsonElement root)
    {
        document.WriteBundle(root.GetProperty("outputPath").GetString()!);
        return new { written = true };
    }
}
