using System.Runtime.InteropServices;
using System.Text;
using UnityAssetEditor.AssetToolsBridge.Managed;

namespace UnityAssetEditor.AssetToolsBridge.Native;

public static unsafe class NativeExports
{
    [UnmanagedCallersOnly(EntryPoint = "uae_bridge_add")]
    public static int Add(int left, int right) => left + right;

    [UnmanagedCallersOnly(EntryPoint = "uae_bridge_inspect")]
    public static int Inspect(byte* pathUtf8, byte* outputBuffer, int outputCapacity)
    {
        if (pathUtf8 is null || outputBuffer is null || outputCapacity <= 0)
            return -1;

        var path = ReadUtf8(pathUtf8);
        if (path is null)
            return -2;

        var json = BridgeApi.InspectJson(path);
        var bytes = Encoding.UTF8.GetBytes(json);
        if (bytes.Length > outputCapacity)
            return -3;

        Marshal.Copy(bytes, 0, (nint)outputBuffer, bytes.Length);
        return bytes.Length;
    }

    private static string? ReadUtf8(byte* value)
    {
        var length = 0;
        while (value[length] != 0)
        {
            length++;
            if (length > 32_768)
                return null;
        }

        return Encoding.UTF8.GetString(value, length);
    }
}
