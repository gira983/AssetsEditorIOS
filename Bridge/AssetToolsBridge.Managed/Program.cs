using AssetToolsBridge.Managed;

internal static class Program
{
    private const int Success = 0;
    private const int InvalidArguments = 2;
    private const int OperationFailed = 1;

    private static int Main(string[] args)
    {
        if (args.Length == 0)
            return Fail(InvalidArguments, "usage: inspect <path> | execute <request-json>");

        try
        {
            return args[0] switch
            {
                "inspect" => Inspect(args),
                "execute" => Execute(args),
                _ => Fail(InvalidArguments, $"unknown command: {args[0]}")
            };
        }
        catch (Exception exception)
        {
            return Fail(OperationFailed, exception.ToString());
        }
    }

    private static int Inspect(string[] args)
    {
        if (args.Length != 2)
            return Fail(InvalidArguments, "usage: inspect <path>");

        Console.Out.Write(BridgeApi.Inspect(args[1]));
        return Success;
    }

    private static int Execute(string[] args)
    {
        if (args.Length != 2)
            return Fail(InvalidArguments, "usage: execute <request-json>");

        Console.Out.Write(BridgeApi.Execute(args[1]));
        return Success;
    }

    private static int Fail(int code, string message)
    {
        Console.Error.WriteLine(message);
        return code;
    }
}
