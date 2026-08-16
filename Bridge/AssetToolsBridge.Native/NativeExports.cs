using System.Runtime.InteropServices;

namespace UnityAssetEditor.AssetToolsBridge.Native;

public static class NativeExports
{
    [UnmanagedCallersOnly(EntryPoint = "uae_bridge_add")]
    public static int Add(int left, int right) => left + right;
}
