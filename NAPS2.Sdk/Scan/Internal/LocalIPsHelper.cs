using System.Net;
using System.Net.NetworkInformation;

namespace NAPS2.Scan.Internal;

internal static class LocalIPsHelper
{
    public static Task<HashSet<string>> Get()
    {
        return Task.Run(() =>
            NetworkInterface.GetAllNetworkInterfaces()
                .SelectMany(x => x.GetIPProperties().UnicastAddresses)
                .Select(x => x.Address.ToString())
                .ToHashSet());
    }

    /// <summary>
    /// Returns true when a device at the given IP should be hidden because it is on a local (non-loopback) address.
    /// Loopback addresses are kept visible because they represent USB scanners bridged by ipp-usb, not ScanServer duplicates.
    /// </summary>
    public static bool ShouldExcludeByLocalIP(string ip, ISet<string> localIPs)
    {
        if (!localIPs.Contains(ip))
        {
            return false;
        }
        return !IPAddress.TryParse(ip, out var parsedIP) || !IPAddress.IsLoopback(parsedIP);
    }

    public static bool ShouldExcludeByLocalIP(IPAddress ip, ISet<string> localIPs) =>
        ShouldExcludeByLocalIP(ip.ToString(), localIPs);
}