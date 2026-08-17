using System.Text.Json;
using AssetsTools.NET;
using AssetsTools.NET.Extra;

namespace AssetToolsBridge.Managed;

public static class BridgeApi
{
    public static string Inspect(string path)
    {
        using var document = BridgeDocument.Open(path);
        return JsonSerializer.Serialize(new
        {
            info = document.GetInfo(),
            assets = document.ListAssets()
        });
    }
}

public sealed record BridgeInfo(string FileName, string Format, string? UnityVersion, int AssetCount);
public sealed record BridgeAsset(string FileName, long PathId, int ClassId, long ByteSize, string AssetType, string? Name);

internal sealed class BridgeDocument : IDisposable
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

    public BridgeInfo GetInfo()
    {
        if (assetsFile is not null)
        {
            var file = assetsFile.file;
            return new BridgeInfo(Path.GetFileName(file.path), "SerializedFile", file.Metadata.UnityVersion, file.AssetInfos.Count);
        }

        if (bundleFile is not null)
            return new BridgeInfo(Path.GetFileName(bundleFile.path), "AssetBundle", null, bundleFile.file.bundleInf6.dirInf.Count);

        throw new InvalidOperationException("No document is open.");
    }

    public IReadOnlyList<BridgeAsset> ListAssets()
    {
        if (assetsFile is not null)
        {
            return assetsFile.file.AssetInfos.Select(info => new BridgeAsset(
                Path.GetFileName(assetsFile.path),
                info.index,
                info.curFileType,
                info.curFileSize,
                info.curFileType.ToString(),
                null)).ToArray();
        }

        if (bundleFile is not null)
        {
            return bundleFile.file.bundleInf6.dirInf.Select(entry => new BridgeAsset(
                entry.name,
                entry.offset,
                0,
                entry.size,
                "BundleEntry",
                entry.name)).ToArray();
        }

        return Array.Empty<BridgeAsset>();
    }

    public void Dispose() => manager.UnloadAll();

    private static bool IsBundle(string path)
    {
        using var stream = File.OpenRead(path);
        Span<byte> header = stackalloc byte[7];
        var read = stream.Read(header);
        var text = System.Text.Encoding.ASCII.GetString(header[..read]);
        return text is "UnityFS" or "UnityRaw" or "UnityWeb";
    }
}
