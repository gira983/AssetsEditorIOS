using AssetsTools.NET;
using AssetsTools.NET.Extra;
using System.Globalization;
using System.Text;
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

    public static BridgeDocument Open(string path, string? classDatabasePath = null)
    {
        if (!File.Exists(path))
            throw new FileNotFoundException("Input file was not found.", path);

        var manager = new AssetsManager
        {
            UseTemplateFieldCache = true,
            UseMonoTemplateFieldCache = true,
            UseRefTypeManagerCache = true,
            UseQuickLookup = true
        };
        try
        {
            if (!string.IsNullOrWhiteSpace(classDatabasePath))
            {
                if (!File.Exists(classDatabasePath))
                    throw new FileNotFoundException("The Unity class database was not found.", classDatabasePath);
                manager.LoadClassPackage(classDatabasePath);
            }

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
            manager.UnloadAll(true);
            throw;
        }
    }

    public string Inspect()
    {
        if (assetsFile is not null)
        {
            var assets = new StringBuilder("[");
            for (var index = 0; index < assetsFile.file.AssetInfos.Count; index++)
            {
                if (index > 0) assets.Append(',');
                var info = assetsFile.file.AssetInfos[index];
                var typeId = info.GetTypeId(assetsFile.file);
                var typeName = GetTypeName(typeId);
                var displayName = GetDisplayName(info, typeName);
                assets.Append("{\"fileName\":").Append(JsonString(Path.GetFileName(assetsFile.path)))
                    .Append(",\"pathId\":").Append(info.PathId)
                    .Append(",\"classId\":").Append(typeId)
                    .Append(",\"byteSize\":").Append(info.ByteSize)
                    .Append(",\"assetType\":").Append(JsonString(typeName))
                    .Append(",\"name\":").Append(JsonString(displayName)).Append('}');
            }
            assets.Append(']');
            return "{\"info\":{\"path\":" + JsonString(assetsFile.path) + ",\"kind\":\"serializedFile\",\"assetCount\":" + assetsFile.file.AssetInfos.Count + ",\"unityVersion\":" + JsonString(assetsFile.file.Metadata.UnityVersion) + "},\"assets\":" + assets + "}";
        }

        if (bundleFile is not null)
        {
            var assets = new StringBuilder("[");
            for (var index = 0; index < bundleFile.file.BlockAndDirInfo.DirectoryInfos.Count; index++)
            {
                if (index > 0) assets.Append(',');
                var directory = bundleFile.file.BlockAndDirInfo.DirectoryInfos[index];
                assets.Append("{\"fileName\":").Append(JsonString(directory.Name))
                    .Append(",\"pathId\":0,\"classId\":0,\"byteSize\":").Append(directory.DecompressedSize)
                    .Append(",\"assetType\":\"bundleEntry\",\"name\":").Append(JsonString(directory.Name)).Append('}');
            }
            assets.Append(']');
            return "{\"info\":{\"path\":" + JsonString(bundleFile.path) + ",\"kind\":\"assetBundle\",\"assetCount\":" + bundleFile.file.BlockAndDirInfo.DirectoryInfos.Count + ",\"unityVersion\":" + JsonString(bundleFile.file.Header.EngineVersion) + "},\"assets\":" + assets + "}";
        }

        throw new InvalidOperationException("The document has no loaded file.");
    }

    public string ListObjects()
    {
        var objects = new StringBuilder("[{0}");
        if (assetsFile is null) return "{\"objects\":[]}";
        objects.Clear().Append('[');
        for (var index = 0; index < assetsFile.file.AssetInfos.Count; index++)
        {
            if (index > 0) objects.Append(',');
            var info = assetsFile.file.AssetInfos[index];
            var typeId = info.GetTypeId(assetsFile.file);
            var typeName = GetTypeName(typeId);
            var displayName = GetDisplayName(info, typeName);
            objects.Append("{\"id\":").Append(JsonString($"{info.PathId}:{typeId}"))
                .Append(",\"pathID\":").Append(info.PathId)
                .Append(",\"typeID\":").Append(typeId)
                .Append(",\"byteOffset\":").Append((ulong)info.GetAbsoluteByteOffset(assetsFile.file.Header))
                .Append(",\"byteSize\":").Append((ulong)info.ByteSize)
                .Append(",\"typeName\":").Append(JsonString(typeName))
                .Append(",\"displayName\":").Append(JsonString(displayName))
                .Append('}');
        }
        objects.Append(']');
        return "{\"objects\":" + objects + "}";
    }

    public string GetFields(long pathId)
    {
        if (assetsFile is null) throw new InvalidOperationException("Fields are available only for serialized files.");
        var info = assetsFile.file.GetAssetInfo(pathId) ?? throw new KeyNotFoundException($"Asset {pathId} was not found.");
        var field = manager.GetBaseField(assetsFile, info) ?? throw new InvalidDataException("This object has no readable TypeTree or class-database definition.");
        var fields = new StringBuilder("[");
        var result = new FieldResult(fields);
        Flatten(field, string.Empty, 0, result);
        fields.Append(']');
        return "{\"fields\":" + fields + "}";
    }

    public void UpdateField(long pathId, string fieldPath, string value, string outputPath)
    {
        if (assetsFile is null) throw new InvalidOperationException("Field updates are available only for serialized files.");
        var info = assetsFile.file.GetAssetInfo(pathId) ?? throw new KeyNotFoundException($"Asset {pathId} was not found.");
        var field = manager.GetBaseField(assetsFile, info) ?? throw new InvalidDataException("This object has no readable TypeTree or class-database definition.");
        var target = field[fieldPath];
        if (target.IsDummy) throw new KeyNotFoundException($"Field {fieldPath} was not found.");
        SetValue(target, value);
        info.SetNewData(field.WriteToByteArray(assetsFile.file.Reader.BigEndian));
        WriteSerializedFile(outputPath);
    }

    public void WriteBundle(string outputPath)
    {
        if (bundleFile is null) throw new InvalidOperationException("The opened document is not an AssetBundle.");
        EnsureParentDirectory(outputPath);
        using var writer = new AssetsFileWriter(outputPath);
        bundleFile.file.Write(writer);
    }

    private sealed class FieldResult
    {
        public StringBuilder Builder { get; }
        public bool IsFirst { get; set; } = true;
        public FieldResult(StringBuilder builder) => Builder = builder;
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

    private static void Flatten(AssetTypeValueField field, string path, int depth, FieldResult result)
    {
        if (field.Children.Count == 0)
        {
            var fieldPath = string.IsNullOrEmpty(path) ? field.FieldName : path;
            if (!result.IsFirst) result.Builder.Append(',');
            result.IsFirst = false;
            result.Builder.Append("{\"id\":").Append(JsonString(fieldPath))
                .Append(",\"name\":").Append(JsonString(fieldPath))
                .Append(",\"type\":").Append(JsonString(field.TypeName))
                .Append(",\"value\":").Append(JsonString(field.AsString))
                .Append(",\"depth\":").Append(depth)
                .Append(",\"editable\":").Append(field.TemplateField.HasValue ? "true" : "false")
                .Append('}');
            return;
        }
        foreach (var child in field.Children)
        {
            var childPath = string.IsNullOrEmpty(path) ? child.FieldName : $"{path}.{child.FieldName}";
            Flatten(child, childPath, depth + 1, result);
        }
    }

    private string GetTypeName(int typeId)
    {
        var type = manager.ClassDatabase?.FindAssetClassByID(typeId);
        return type is null ? typeId.ToString(CultureInfo.InvariantCulture) : manager.ClassDatabase!.GetString(type.Name);
    }

    private string GetDisplayName(AssetFileInfo info, string typeName)
    {
        if (manager.ClassDatabase is not null)
        {
            try
            {
                var name = AssetHelper.GetAssetNameFast(assetsFile!.file, manager.ClassDatabase, info);
                if (!string.IsNullOrWhiteSpace(name)) return name;
            }
            catch
            {
            }
        }
        return $"{typeName} • {info.PathId}";
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

    private static string JsonString(string? value)
    {
        if (value is null) return "null";
        var builder = new StringBuilder(value.Length + 2).Append('\"');
        foreach (var character in value)
        {
            switch (character)
            {
                case '\\': builder.Append("\\\\"); break;
                case '\"': builder.Append("\\\""); break;
                case '\b': builder.Append("\\b"); break;
                case '\f': builder.Append("\\f"); break;
                case '\n': builder.Append("\\n"); break;
                case '\r': builder.Append("\\r"); break;
                case '\t': builder.Append("\\t"); break;
                default:
                    if (character < 0x20) builder.Append("\\u").Append(((int)character).ToString("x4", CultureInfo.InvariantCulture));
                    else builder.Append(character);
                    break;
            }
        }
        return builder.Append('\"').ToString();
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
    public static string Execute(string request)
    {
        using var document = JsonDocument.Parse(request);
        var root = document.RootElement;
        var operation = root.GetProperty("operation").GetString() ?? throw new InvalidDataException("Missing operation.");
        var path = root.GetProperty("path").GetString() ?? throw new InvalidDataException("Missing path.");
        var classDatabasePath = root.TryGetProperty("classDatabasePath", out var classDatabase)
            ? classDatabase.GetString()
            : null;
        using var opened = BridgeDocument.Open(path, classDatabasePath);
        var result = operation switch
        {
            "inspect" => opened.Inspect(),
            "listObjects" => opened.ListObjects(),
            "getFields" => opened.GetFields(root.GetProperty("pathId").GetInt64()),
            "updateField" => Update(opened, root),
            "writeBundle" => WriteBundle(opened, root),
            _ => throw new NotSupportedException($"Unknown operation: {operation}")
        };
        return "{\"ok\":true,\"result\":" + result + "}";
    }

    public static string Error(string message) => "{\"ok\":false,\"error\":" + JsonString(message) + "}";

    public static string Inspect(string path) => Execute("{\"operation\":\"inspect\",\"path\":" + JsonString(path) + "}");

    private static string Update(BridgeDocument document, JsonElement root)
    {
        document.UpdateField(root.GetProperty("pathId").GetInt64(), root.GetProperty("fieldPath").GetString()!, root.GetProperty("value").GetString()!, root.GetProperty("outputPath").GetString()!);
        return "{\"written\":true}";
    }

    private static string WriteBundle(BridgeDocument document, JsonElement root)
    {
        document.WriteBundle(root.GetProperty("outputPath").GetString()!);
        return "{\"written\":true}";
    }

    private static string JsonString(string? value)
    {
        if (value is null) return "null";
        var builder = new StringBuilder(value.Length + 2).Append('\"');
        foreach (var character in value)
        {
            switch (character)
            {
                case '\\': builder.Append("\\\\"); break;
                case '\"': builder.Append("\\\""); break;
                case '\b': builder.Append("\\b"); break;
                case '\f': builder.Append("\\f"); break;
                case '\n': builder.Append("\\n"); break;
                case '\r': builder.Append("\\r"); break;
                case '\t': builder.Append("\\t"); break;
                default:
                    if (character < 0x20) builder.Append("\\u").Append(((int)character).ToString("x4", CultureInfo.InvariantCulture));
                    else builder.Append(character);
                    break;
            }
        }
        return builder.Append('\"').ToString();
    }
}
