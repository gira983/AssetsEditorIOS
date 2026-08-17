using System.Runtime.InteropServices;
using System.Text;
using AssetToolsBridge.Managed;

namespace AssetToolsBridge.Native;

public static unsafe class NativeExports
{
    [UnmanagedCallersOnly(EntryPoint = "uae_bridge_inspect")]
    public static int Inspect(byte* pathUtf8, byte* outputUtf8, int outputCapacity)
    {
        if (pathUtf8 == null || outputUtf8 == null || outputCapacity <= 0)
            return -1;

        try
        {
            var path = ReadUtf8(pathUtf8);
            if (path is null)
                return -1;

            var json = BridgeApi.Inspect(path);
            var bytes = Encoding.UTF8.GetBytes(json);
            if (bytes.Length + 1 > outputCapacity)
                return -3;

            bytes.CopyTo(new Span<byte>(outputUtf8, outputCapacity));
            outputUtf8[bytes.Length] = 0;
            return bytes.Length;
        }
        catch
        {
            return -2;
        }
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

        return Encoding.UTF8.GetString(new ReadOnlySpan<byte>(value, length));
    }
}
