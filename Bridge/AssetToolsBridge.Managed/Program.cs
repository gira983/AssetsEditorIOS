using System.Text;

namespace UnityAssetEditor.AssetToolsBridge.Managed;

internal static class Program
{
    private const int Success = 0;
    private const int InvalidArguments = 2;
    private const int OperationFailed = 1;

    private static int Main(string[] args)
    {
        if (args.Length == 0)
            return Fail(InvalidArguments, "usage: inspect <path>");

        try
        {
            return args[0] switch
            {
                "inspect" => Inspect(args),
                _ => Fail(InvalidArguments, $"unknown command: {args[0]}")
            };
        }
        catch (Exception exception)
        {
            return Fail(OperationFailed, exception.Message);
        }
    }

    private static int Inspect(string[] args)
    {
        if (args.Length != 2)
            return Fail(InvalidArguments, "usage: inspect <path>");

        Console.Out.Write(BridgeApi.InspectJson(args[1]));
        return Success;
    }

    private static int Fail(int code, string message)
    {
        Console.Error.WriteLine(message);
        return code;
    }
}
