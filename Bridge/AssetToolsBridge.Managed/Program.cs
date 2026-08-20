using AssetToolsBridge.Managed;
using AssetsTools.NET.Extra;

internal static class Program
{
    private const int Success = 0;
    private const int InvalidArguments = 2;
    private const int OperationFailed = 1;

    private static int Main(string[] args)
    {
        if (args.Length == 0)
            return Fail(InvalidArguments, "usage: inspect <path> [classdata.tpk] | execute <request-json>");

        try
        {
            return args[0] switch
            {
                "inspect" => Inspect(args),
                "classdata-check" => ClassDataCheck(args),
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
        if (args.Length is < 2 or > 3)
            return Fail(InvalidArguments, "usage: inspect <path> [classdata.tpk]");

        var request = "{\"operation\":\"inspect\",\"path\":" + JsonString(args[1]);
        if (args.Length == 3)
            request += ",\"classDatabasePath\":" + JsonString(args[2]);
        request += "}";
        Console.Out.Write(BridgeApi.Execute(request));
        return Success;
    }

    private static int ClassDataCheck(string[] args)
    {
        if (args.Length != 2)
            return Fail(InvalidArguments, "usage: classdata-check <classdata.tpk>");

        var manager = new AssetsManager();
        try
        {
            manager.LoadClassPackage(args[1]);
            if (manager.ClassPackage is null)
                return Fail(OperationFailed, "AssetsTools.NET did not load the class package.");
            Console.Out.Write("{\"ok\":true}");
            return Success;
        }
        finally
        {
            manager.UnloadAll(true);
        }
    }

    private static string JsonString(string value)
    {
        return System.Text.Json.JsonSerializer.Serialize(value);
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
