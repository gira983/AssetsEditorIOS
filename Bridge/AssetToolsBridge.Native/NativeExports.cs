using System;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using AssetToolsBridge.Managed;

namespace AssetToolsBridge.Native;

public static class NativeExports
{
    [UnmanagedCallersOnly(EntryPoint = "NativeAOT_StaticInitialization", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static void NativeAOTStaticInitialization()
    {
    }

    [UnmanagedCallersOnly(EntryPoint = "uae_bridge_initialize", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static int Initialize()
    {
        try
        {
            BridgeApi.Initialize();
            return 0;
        }
        catch
        {
            return -1;
        }
    }

    [UnmanagedCallersOnly(EntryPoint = "uae_bridge_execute", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static unsafe IntPtr Execute(byte* requestUtf8, int requestLength)
    {
        if (requestUtf8 == null || requestLength < 0)
        {
            return IntPtr.Zero;
        }

        try
        {
            BridgeApi.Initialize();
            var request = ReadUtf8(requestUtf8, requestLength);
            var response = BridgeApi.Execute(request);
            return Marshal.StringToCoTaskMemUTF8(response);
        }
        catch (Exception exception)
        {
            var response = JsonSerializer.Serialize(new { ok = false, error = exception.Message });
            return Marshal.StringToCoTaskMemUTF8(response);
        }
    }

    [UnmanagedCallersOnly(EntryPoint = "uae_bridge_free", CallConvs = new[] { typeof(CallConvCdecl) })]
    public static void Free(IntPtr value)
    {
        if (value != IntPtr.Zero)
        {
            Marshal.FreeCoTaskMem(value);
        }
    }

    private static unsafe string ReadUtf8(byte* pointer, int length)
    {
        return Encoding.UTF8.GetString(new ReadOnlySpan<byte>(pointer, length));
    }
}
