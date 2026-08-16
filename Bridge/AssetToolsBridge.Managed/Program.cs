using System.Globalization;
using System.Text.Json;
using AssetsTools.NET;
using AssetsTools.NET.Extra;

namespace UnityAssetEditor.AssetToolsBridge.Managed;

internal static class Program
{
    private const int Success = 0;
    private const int InvalidArguments = 2;
    private const int OperationFailed = 1;
    private const int MaxFields = 4000;
    private const int MaxDepth = 64;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = false,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private static int Main(string[] args)
    {
        try
        {
            if (args.Length == 0)
            {
                WriteError("missing command");
                return InvalidArguments;
            }

            return args[0] switch
            {
                "inspect" => Inspect(args),
                "objects" => Objects(args),
                "fields" => Fields(args),
                "edit" => Edit(args),
                "bundle-entries" => BundleEntries(args),
                "extract" => Extract(args),
                _ => Fail(InvalidArguments, $"unknown command: {args[0]}")
            };
        }
        catch (Exception exception)
        {
            return Fail(OperationFailed, exception.Message);
        }
    }

    internal static string Inspect(string path)
    {
        using FileStream stream = File.OpenRead(path);
        AssetsFileReader reader = new(stream);
        if (AssetsFile.IsAssetsFile(reader, 0, stream.Length))
        {
            stream.Position = 0;
            AssetsFile assetsFile = new();
            assetsFile.Read(new AssetsFileReader(stream));
            return JsonSerializer.Serialize(new
            {
                kind = "serializedFile",
                formatVersion = assetsFile.Header.Version,
                fileSize = assetsFile.Header.FileSize,
                metadataSize = assetsFile.Header.MetadataSize,
                dataOffset = assetsFile.Header.DataOffset,
                unityVersion = assetsFile.Metadata.UnityVersion,
                targetPlatform = assetsFile.Metadata.TargetPlatform,
                objectCount = assetsFile.Metadata.AssetInfos.Count,
                typeCount = assetsFile.Metadata.TypeTreeTypes.Count,
                externalCount = assetsFile.Metadata.Externals.Count,
                isBigEndian = assetsFile.Header.Endianness,
                typeTreeEnabled = assetsFile.Metadata.TypeTreeEnabled
            }, JsonOptions);
        }

        stream.Position = 0;
        AssetBundleFile bundle = new();
        bundle.Read(new AssetsFileReader(stream));
        return JsonSerializer.Serialize(new
        {
            kind = "assetBundle",
            signature = bundle.Header.Signature,
            formatVersion = bundle.Header.Version,
            unityVersion = bundle.Header.EngineVersion,
            fileSize = bundle.Header.FileStreamHeader.TotalFileSize,
            compressed = bundle.DataIsCompressed,
            blockCount = bundle.BlockAndDirInfo.BlockInfos.Length,
            directoryEntryCount = bundle.BlockAndDirInfo.DirectoryInfos.Count
        }, JsonOptions);
    }

    private static int Inspect(string[] args)
    {
        if (args.Length != 2)
            return Fail(InvalidArguments, "usage: inspect <path>");
        Console.Out.WriteLine(Inspect(args[1]));
        return Success;
    }

    private static int Objects(string[] args)
    {
        if (args.Length != 2)
            return Fail(InvalidArguments, "usage: objects <path>");

        using BridgeDocument document = BridgeDocument.Open(args[1]);
        if (document.Assets is null)
            return Fail(InvalidArguments, "objects is available only for SerializedFiles");

        WriteJson(document.Assets.File.Metadata.AssetInfos.Select(info => new
        {
            id = $"{info.PathId}",
            pathID = info.PathId,
            typeID = info.GetTypeId(document.Assets.File),
            byteOffset = info.GetAbsoluteByteOffset(document.Assets.File),
            byteSize = info.ByteSize,
            typeName = TypeName(document.Assets, info),
            displayName = $"{TypeName(document.Assets, info)} ({info.PathId})"
        }));
        return Success;
    }

    private static int Fields(string[] args)
    {
        if (args.Length != 3 || !long.TryParse(args[2], out long pathID))
            return Fail(InvalidArguments, "usage: fields <path> <pathID>");

        using BridgeDocument document = BridgeDocument.Open(args[1]);
        if (document.Assets is null)
            return Fail(InvalidArguments, "fields is available only for SerializedFiles");

        AssetFileInfo info = document.Assets.File.GetAssetInfo(pathID) ?? throw new InvalidDataException("object not found");
        AssetTypeValueField baseField = document.Manager.GetBaseField(document.Assets, info);
        List<FieldRow> fields = new();
        Walk(baseField, baseField.FieldName, 0, fields);
        WriteJson(fields);
        return Success;
    }

    private static int Edit(string[] args)
    {
        if (args.Length != 5 || !long.TryParse(args[2], out long pathID))
            return Fail(InvalidArguments, "usage: edit <path> <pathID> <fieldPath> <value>");

        string path = args[1];
        string tempPath = path + ".uae-edit-" + Guid.NewGuid().ToString("N");
        try
        {
            using BridgeDocument document = BridgeDocument.Open(path);
            if (document.Assets is null)
                return Fail(InvalidArguments, "edit is available only for SerializedFiles");

            AssetFileInfo info = document.Assets.File.GetAssetInfo(pathID) ?? throw new InvalidDataException("object not found");
            AssetTypeValueField baseField = document.Manager.GetBaseField(document.Assets, info);
            AssetTypeValueField field = FindField(baseField, args[3]) ?? throw new InvalidDataException($"field not found: {args[3]}");
            SetField(field, args[4]);
            info.SetNewData(baseField.WriteToByteArray());

            using FileStream output = File.Create(tempPath);
            using AssetsFileWriter writer = new(output);
            document.Assets.File.Write(writer);
            File.Move(tempPath, path, true);
            WriteJson(new { ok = true, pathID, fieldPath = args[3] });
            return Success;
        }
        finally
        {
            if (File.Exists(tempPath))
                File.Delete(tempPath);
        }
    }

    private static int BundleEntries(string[] args)
    {
        if (args.Length != 2)
            return Fail(InvalidArguments, "usage: bundle-entries <path>");

        using BridgeDocument document = BridgeDocument.Open(args[1]);
        if (document.Bundle is null)
            return Fail(InvalidArguments, "bundle-entries is available only for AssetBundles");

        WriteJson(document.Bundle.File.BlockAndDirInfo.DirectoryInfos.Select((entry, index) => new
        {
            id = index,
            name = entry.Name,
            offset = entry.Offset,
            decompressedSize = entry.DecompressedSize,
            flags = entry.Flags
        }));
        return Success;
    }

    private static int Extract(string[] args)
    {
        if (args.Length != 4 || !int.TryParse(args[2], out int index))
            return Fail(InvalidArguments, "usage: extract <path> <entryIndex> <outputPath>");

        using BridgeDocument document = BridgeDocument.Open(args[1]);
        if (document.Bundle is null)
            return Fail(InvalidArguments, "extract is available only for AssetBundles");
        if (index < 0 || index >= document.Bundle.File.BlockAndDirInfo.DirectoryInfos.Count)
            return Fail(InvalidArguments, "entry index is out of range");

        document.Bundle.File.GetFileRange(index, out long offset, out long length);
        document.Bundle.File.DataReader.Position = offset;
        byte[] data = document.Bundle.File.DataReader.ReadBytes((int)length);
        File.WriteAllBytes(args[3], data);
        WriteJson(new { ok = true, path = args[3], bytes = data.Length });
        return Success;
    }

    private static string TypeName(AssetsFileInstance assets, AssetFileInfo info)
    {
        int typeID = info.GetTypeId(assets.File);
        return Enum.IsDefined(typeof(AssetClassID), typeID)
            ? ((AssetClassID)typeID).ToString()
            : $"ClassID {typeID}";
    }

    private static void Walk(AssetTypeValueField field, string path, int depth, List<FieldRow> output)
    {
        if (output.Count >= MaxFields || depth > MaxDepth || field.IsDummy)
            return;

        string value = ValueString(field);
        bool editable = field.Children.Count == 0 && field.TemplateField.ValueType is not AssetValueType.None and not AssetValueType.Array;
        output.Add(new FieldRow($"{depth}:{path}", path, field.TypeName, value, depth, editable));

        if (field.TemplateField.ValueType == AssetValueType.ByteArray)
            return;
        for (int index = 0; index < field.Children.Count && output.Count < MaxFields; index++)
        {
            AssetTypeValueField child = field.Children[index];
            string childPath = field.TemplateField.IsArray ? $"{path}[{index}]" : $"{path}.{child.FieldName}";
            Walk(child, childPath, depth + 1, output);
        }
    }

    private static AssetTypeValueField? FindField(AssetTypeValueField root, string path)
    {
        string normalized = path == root.FieldName ? string.Empty : path.StartsWith(root.FieldName + ".", StringComparison.Ordinal) ? path[(root.FieldName.Length + 1)..] : path;
        if (normalized.Length == 0)
            return root;

        AssetTypeValueField current = root;
        foreach (string segment in normalized.Split('.', StringSplitOptions.RemoveEmptyEntries))
        {
            int bracket = segment.IndexOf('[');
            if (bracket >= 0)
            {
                string name = segment[..bracket];
                int endBracket = segment.IndexOf(']', bracket + 1);
                if (endBracket < 0 || !int.TryParse(segment[(bracket + 1)..endBracket], out int index))
                    return null;
                if (name.Length > 0)
                    current = current[name];
                if (index < 0 || index >= current.Children.Count)
                    return null;
                current = current[index];
            }
            else
            {
                current = current[segment];
            }
            if (current.IsDummy)
                return null;
        }
        return current;
    }

    private static void SetField(AssetTypeValueField field, string value)
    {
        switch (field.TemplateField.ValueType)
        {
            case AssetValueType.String:
                field.AsString = value;
                return;
            case AssetValueType.Bool when bool.TryParse(value, out bool booleanValue):
                field.AsBool = booleanValue;
                return;
            case AssetValueType.Int8 when sbyte.TryParse(value, out sbyte int8):
                field.AsSByte = int8;
                return;
            case AssetValueType.UInt8 when byte.TryParse(value, out byte uint8):
                field.AsByte = uint8;
                return;
            case AssetValueType.Int16 when short.TryParse(value, out short int16):
                field.AsShort = int16;
                return;
            case AssetValueType.UInt16 when ushort.TryParse(value, out ushort uint16):
                field.AsUShort = uint16;
                return;
            case AssetValueType.Int32 when int.TryParse(value, out int int32):
                field.AsInt = int32;
                return;
            case AssetValueType.UInt32 when uint.TryParse(value, out uint uint32):
                field.AsUInt = uint32;
                return;
            case AssetValueType.Int64 when long.TryParse(value, out long int64):
                field.AsLong = int64;
                return;
            case AssetValueType.UInt64 when ulong.TryParse(value, out ulong uint64):
                field.AsULong = uint64;
                return;
            case AssetValueType.Float when float.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out float single):
                field.AsFloat = single;
                return;
            case AssetValueType.Double when double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out double doubleValue):
                field.AsDouble = doubleValue;
                return;
            default:
                throw new InvalidDataException($"unsupported or invalid value for {field.TypeName}: {value}");
        }
    }

    private static string ValueString(AssetTypeValueField field)
    {
        return field.TemplateField.ValueType switch
        {
            AssetValueType.String => field.AsString,
            AssetValueType.Bool => field.AsBool.ToString().ToLowerInvariant(),
            AssetValueType.Int8 => field.AsSByte.ToString(),
            AssetValueType.UInt8 => field.AsByte.ToString(),
            AssetValueType.Int16 => field.AsShort.ToString(),
            AssetValueType.UInt16 => field.AsUShort.ToString(),
            AssetValueType.Int32 => field.AsInt.ToString(),
            AssetValueType.UInt32 => field.AsUInt.ToString(),
            AssetValueType.Int64 => field.AsLong.ToString(),
            AssetValueType.UInt64 => field.AsULong.ToString(),
            AssetValueType.Float => field.AsFloat.ToString("R", CultureInfo.InvariantCulture),
            AssetValueType.Double => field.AsDouble.ToString("R", CultureInfo.InvariantCulture),
            AssetValueType.ByteArray => $"[{field.AsByteArray.Length} bytes]",
            AssetValueType.Array => $"[{field.Children.Count} items]",
            _ => string.Empty
        };
    }

    private static int Fail(int code, string message)
    {
        WriteError(message);
        return code;
    }

    private static void WriteJson<T>(T value)
    {
        Console.Out.WriteLine(JsonSerializer.Serialize(value, JsonOptions));
    }

    private static void WriteError(string message)
    {
        Console.Error.WriteLine(message);
    }

    private sealed record FieldRow(string Id, string Name, string Type, string Value, int Depth, bool Editable);

    private sealed class BridgeDocument : IDisposable
    {
        public AssetsManager Manager { get; }
        public AssetsFileInstance? Assets { get; }
        public BundleFileInstance? Bundle { get; }

        private BridgeDocument(AssetsManager manager, AssetsFileInstance? assets, BundleFileInstance? bundle)
        {
            Manager = manager;
            Assets = assets;
            Bundle = bundle;
        }

        public static BridgeDocument Open(string path)
        {
            AssetsManager manager = new() { UseQuickLookup = true };
            try
            {
                using FileStream stream = File.OpenRead(path);
                AssetsFileReader reader = new(stream);
                if (AssetsFile.IsAssetsFile(reader, 0, stream.Length))
                {
                    AssetsFileInstance assets = manager.LoadAssetsFile(path, false);
                    return new BridgeDocument(manager, assets, null);
                }

                BundleFileInstance bundle = manager.LoadBundleFile(path, true);
                return new BridgeDocument(manager, null, bundle);
            }
            catch
            {
                manager.UnloadAll();
                throw;
            }
        }

        public void Dispose()
        {
            Manager.UnloadAll();
        }
    }
}
