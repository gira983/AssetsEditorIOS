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
        if (IsBundle(path))
        {
            var bundle = manager.LoadBundleFile(path, true);
            if (bundle is null)
                throw new InvalidDataException("AssetsTools.NET could not load the bundle.");
            return new BridgeDocument(manager, null, bundle);
        }

        var assets = manager.LoadAssetsFile(path, true);
        if (assets is null)
            throw new InvalidDataException("AssetsTools.NET could not load the serialized file.");
        return new BridgeDocument(manager, assets, null);
    }

    public BridgeDocumentInfo GetInfo()
    {
        if (assetsFile is not null)
        {
            var file = assetsFile.file;
            return new BridgeDocumentInfo(
                assetsFile.path,
                "serialized-file",
                file.AssetInfos.Count,
                file.Metadata.UnityVersion);
        }

        if (bundleFile is not null)
        {
            return new BridgeDocumentInfo(
                bundleFile.path,
                "asset-bundle",
                bundleFile.file.DirectoryInfo.Count,
                null);
        }

        throw new InvalidOperationException("No document is open.");
    }

    public IReadOnlyList<BridgeAssetInfo> ListAssets()
    {
        if (assetsFile is null)
            throw new NotSupportedException("Asset listing inside bundles is not exposed by this bridge yet.");

        return assetsFile.file.AssetInfos.Select(info => new BridgeAssetInfo(
            assetsFile.path,
            info.PathId,
            info.TypeId,
            info.ByteSize,
            info.TypeId.ToString(),
            null)).ToArray();
    }

    public void Dispose()
    {
        manager.UnloadAll();
    }

    private static bool IsBundle(string path)
    {
        using var stream = File.OpenRead(path);
        Span<byte> magic = stackalloc byte[7];
        var read = stream.Read(magic);
        return read == 7 && magic.SequenceEqual("UnityFS"u8);
    }
}

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
