using System.Runtime.InteropServices;
using System.Text;

namespace UnityAssetEditor.AssetToolsBridge.Native;

public static class NativeExports
{
    [UnmanagedCallersOnly(EntryPoint = "uae_bridge_add")]
    public static int Add(int left, int right) => left + right;

    [UnmanagedCallersOnly(EntryPoint = "uae_bridge_free")]
    public static void Free(nint pointer)
    {
        if (pointer != nint.Zero)
            Marshal.FreeCoTaskMem(pointer);
    }

    [UnmanagedCallersOnly(EntryPoint = "uae_bridge_version")]
    public static nint Version()
    {
        byte[] bytes = Encoding.UTF8.GetBytes("unityasseteditor-bridge/1\0");
        nint pointer = Marshal.AllocCoTaskMem(bytes.Length);
        Marshal.Copy(bytes, 0, pointer, bytes.Length);
        return pointer;
    }
}
