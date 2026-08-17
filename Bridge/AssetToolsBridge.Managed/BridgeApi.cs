using AssetsTools.NET;
using AssetsTools.NET.Extra;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

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

    public JsonObject Inspect()
    {
        if (assetsFile is not null)
        {
            var assets = new JsonArray();
            foreach (var info in assetsFile.file.AssetInfos)
            {
                var typeId = info.GetTypeId(assetsFile.file);
                assets.Add(new JsonObject
                {
                    ["fileName"] = Path.GetFileName(assetsFile.path),
                    ["pathId"] = info.PathId,
                    ["classId"] = typeId,
                    ["byteSize"] = info.ByteSize,
                    ["assetType"] = typeId.ToString(CultureInfo.InvariantCulture),
                    ["name"] = null
                });
            }

            return new JsonObject
            {
                ["info"] = new JsonObject
                {
                    ["path"] = assetsFile.path,
                    ["kind"] = "serializedFile",
                    ["assetCount"] = assetsFile.file.AssetInfos.Count,
                    ["unityVersion"] = assetsFile.file.Metadata.UnityVersion
                },
                ["assets"] = assets
            };
        }

        if (bundleFile is not null)
        {
            var assets = new JsonArray();
            foreach (var directory in bundleFile.file.BlockAndDirInfo.DirectoryInfos)
            {
                assets.Add(new JsonObject
                {
                    ["fileName"] = directory.Name,
                    ["pathId"] = 0L,
                    ["classId"] = 0,
                    ["byteSize"] = (long)directory.DecompressedSize,
                    ["assetType"] = "bundleEntry",
                    ["name"] = directory.Name
                });
            }

            return new JsonObject
            {
                ["info"] = new JsonObject
                {
                    ["path"] = bundleFile.path,
                    ["kind"] = "assetBundle",
                    ["assetCount"] = bundleFile.file.BlockAndDirInfo.DirectoryInfos.Count,
                    ["unityVersion"] = bundleFile.file.Header.EngineVersion
                },
                ["assets"] = assets
            };
        }

        throw new InvalidOperationException("The document has no loaded file.");
    }

    public JsonObject ListObjects()
    {
        var objects = new JsonArray();
        if (assetsFile is null)
            return new JsonObject { ["objects"] = objects };

        foreach (var info in assetsFile.file.AssetInfos)
        {
            var typeId = info.GetTypeId(assetsFile.file);
            objects.Add(new JsonObject
            {
                ["id"] = $"{info.PathId}:{typeId}",
                ["pathID"] = info.PathId,
                ["typeID"] = typeId,
                ["byteOffset"] = (ulong)info.GetAbsoluteByteOffset(assetsFile.file.Header),
                ["byteSize"] = (ulong)info.ByteSize,
                ["typeName"] = typeId.ToString(CultureInfo.InvariantCulture),
                ["displayName"] = $"{typeId} • {info.PathId}"
            });
        }

        return new JsonObject { ["objects"] = objects };
    }

    public JsonObject GetFields(long pathId)
    {
        if (assetsFile is null)
            throw new InvalidOperationException("Fields are available only for serialized files.");

        var info = assetsFile.file.GetAssetInfo(pathId) ?? throw new KeyNotFoundException($"Asset {pathId} was not found.");
        var field = manager.GetBaseField(assetsFile, info);
        var fields = new JsonArray();
        Flatten(field, field.FieldName, 0, fields);
        return new JsonObject { ["fields"] = fields };
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
        info.SetNewData(field.WriteToByteArray(assetsFile.file.Reader.BigEndian));
        WriteSerializedFile(outputPath);
    }

    public void WriteBundle(string outputPath)
    {
        if (bundleFile is null)
            throw new InvalidOperationException("The opened document is not an AssetBundle.");

        EnsureParentDirectory(outputPath);
        using var writer = new AssetsFileWriter(outputPath);
        bundleFile.file.Write(writer);
    }

    public void Dispose() => manager.UnloadAll();

    private void WriteSerializedFile(string outputPath)
    {
        EnsureParentDirectory(outputPath);
        using var writer = new AssetsFileWriter(outputPath);
        assetsFile!.file.Write(writer);
    }

    private static void EnsureParentDirectory(string outputPath)
    {
        var parent = Path.GetDirectoryName(Path.GetFullPath(outputPath));
        if (!string.IsNullOrEmpty(parent))
            Directory.CreateDirectory(parent);
    }

    private static void Flatten(AssetTypeValueField field, string path, int depth, JsonArray result)
    {
        if (field.Children.Count == 0)
        {
            result.Add(new JsonObject
            {
                ["id"] = path,
                ["name"] = path,
                ["type"] = field.TypeName,
                ["value"] = field.AsString,
                ["depth"] = depth,
                ["editable"] = field.TemplateField.HasValue
            });
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
            case AssetValueType.Int8: field.AsSByte = sbyte.Parse(value, CultureInfo.InvariantCulture); break;
            case AssetValueType.UInt8: field.AsByte = byte.Parse(value, CultureInfo.InvariantCulture); break;
            case AssetValueType.Int16: field.AsShort = short.Parse(value, CultureInfo.InvariantCulture); break;
            case AssetValueType.UInt16: field.AsUShort = ushort.Parse(value, CultureInfo.InvariantCulture); break;
            case AssetValueType.Int32: field.AsInt = int.Parse(value, CultureInfo.InvariantCulture); break;
            case AssetValueType.UInt32: field.AsUInt = uint.Parse(value, CultureInfo.InvariantCulture); break;
            case AssetValueType.Int64: field.AsLong = long.Parse(value, CultureInfo.InvariantCulture); break;
            case AssetValueType.UInt64: field.AsULong = ulong.Parse(value, CultureInfo.InvariantCulture); break;
            case AssetValueType.Float: field.AsFloat = float.Parse(value, CultureInfo.InvariantCulture); break;
            case AssetValueType.Double: field.AsDouble = double.Parse(value, CultureInfo.InvariantCulture); break;
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
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = false };

    public static string Execute(string request)
    {
        using var document = JsonDocument.Parse(request);
        var root = document.RootElement;
        var operation = root.GetProperty("operation").GetString() ?? throw new InvalidDataException("Missing operation.");
        var path = root.GetProperty("path").GetString() ?? throw new InvalidDataException("Missing path.");
        using var opened = BridgeDocument.Open(path);
        var result = operation switch
        {
            "inspect" => opened.Inspect(),
            "listObjects" => opened.ListObjects(),
            "getFields" => opened.GetFields(root.GetProperty("pathId").GetInt64()),
            "updateField" => Update(opened, root),
            "writeBundle" => WriteBundle(opened, root),
            _ => throw new NotSupportedException($"Unknown operation: {operation}")
        };
        return new JsonObject { ["ok"] = true, ["result"] = result }.ToJsonString(JsonOptions);
    }

    public static string Error(string message) => new JsonObject { ["ok"] = false, ["error"] = message }.ToJsonString(JsonOptions);

    public static string Inspect(string path) => Execute(new JsonObject { ["operation"] = "inspect", ["path"] = path }.ToJsonString(JsonOptions));

    private static JsonObject Update(BridgeDocument document, JsonElement root)
    {
        document.UpdateField(root.GetProperty("pathId").GetInt64(), root.GetProperty("fieldPath").GetString()!, root.GetProperty("value").GetString()!, root.GetProperty("outputPath").GetString()!);
        return new JsonObject { ["written"] = true };
    }

    private static JsonObject WriteBundle(BridgeDocument document, JsonElement root)
    {
        document.WriteBundle(root.GetProperty("outputPath").GetString()!);
        return new JsonObject { ["written"] = true };
    }
}
