using System.Runtime.InteropServices;
using System.Text;
using AssetToolsBridge.Managed;

namespace AssetToolsBridge.Native;

public static unsafe class NativeExports
{
    [UnmanagedCallersOnly(EntryPoint = "uae_bridge_execute")]
    public static int Execute(byte* requestUtf8, byte* outputUtf8, int outputCapacity)
    {
        if (requestUtf8 == null || outputUtf8 == null || outputCapacity <= 0)
            return -1;

        try
        {
            var request = ReadUtf8(requestUtf8);
            if (request is null)
                return -1;

            return WriteUtf8(BridgeApi.Execute(request), outputUtf8, outputCapacity);
        }
        catch (Exception exception)
        {
            return WriteUtf8(BridgeApi.Failure(exception.Message), outputUtf8, outputCapacity);
        }
    }

    private static int WriteUtf8(string value, byte* destination, int capacity)
    {
        var bytes = Encoding.UTF8.GetBytes(value);
        if (bytes.Length + 1 > capacity)
            return -3;
        bytes.CopyTo(new Span<byte>(destination, capacity));
        destination[bytes.Length] = 0;
        return bytes.Length;
    }

    private static string? ReadUtf8(byte* value)
    {
        var length = 0;
        while (value[length] != 0)
        {
            length++;
            if (length > 1_048_576)
                return null;
        }
        return Encoding.UTF8.GetString(new ReadOnlySpan<byte>(value, length));
    }
}
