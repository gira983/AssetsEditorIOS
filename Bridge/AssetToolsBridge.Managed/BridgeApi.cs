using System.Text.Json;
using AssetsTools.NET;
using AssetsTools.NET.Extra;

namespace UnityAssetEditor.AssetToolsBridge.Managed;

public static class BridgeApi
{
    public static string InspectJson(string path)
    {
        using var document = BridgeDocument.Open(path);
        return JsonSerializer.Serialize(document.Describe());
    }
}

internal sealed class BridgeDocument : IDisposable
{
    private readonly AssetsManager manager;
    private readonly AssetsFileInstance? assets;
    private readonly BundleFileInstance? bundle;

    private BridgeDocument(AssetsManager manager, AssetsFileInstance? assets, BundleFileInstance? bundle)
    {
        this.manager = manager;
        this.assets = assets;
        this.bundle = bundle;
    }

    public static BridgeDocument Open(string path)
    {
        var manager = new AssetsManager();
        try
        {
            if (IsBundle(path))
                return new BridgeDocument(manager, null, manager.LoadBundleFile(path, true));

            return new BridgeDocument(manager, manager.LoadAssetsFile(path, false), null);
        }
        catch
        {
            manager.UnloadAll();
            throw;
        }
    }

    public object Describe()
    {
        if (assets is not null)
        {
            return new
            {
                format = "serialized-file",
                path = assets.path,
                unityVersion = assets.file.Metadata.UnityVersion,
                assetCount = assets.file.AssetInfos.Count
            };
        }

        if (bundle is not null)
        {
            return new
            {
                format = "asset-bundle",
                path = bundle.path,
                entryCount = bundle.file.BlockAndDirInfo.DirectoryInfos.Count,
                entries = bundle.file.GetAllFileNames()
            };
        }

        throw new InvalidOperationException("No document loaded");
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
