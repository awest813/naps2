using System.Threading;
using Microsoft.Extensions.Logging;
using NAPS2.Escl;
using NAPS2.Escl.Client;

namespace NAPS2.Scan.Internal.Escl;

/// <summary>
/// Locates eSCL endpoints exposed on localhost by the ipp-usb daemon, which bridges USB scanners (e.g. Canon
/// imageFORMULA R10) to HTTP. ipp-usb advertises its services via Avahi on the loopback interface only, which our
/// multicast-socket-based mDNS discovery doesn't receive, so we probe its well-known port range directly.
/// </summary>
internal class IppUsbEsclLocator
{
    // ipp-usb allocates one HTTP port per connected device, starting at 60000 (the default "http-min-port" in
    // ipp-usb.conf) and taking the next free port for each additional device.
    private const int PORT_RANGE_START = 60000;
    private const int PORT_RANGE_SIZE = 10;

    // ipp-usb always serves eSCL under this path.
    private const string ROOT_PATH = "eSCL";

    public static IEnumerable<Uri> CandidateUris() =>
        Enumerable.Range(PORT_RANGE_START, PORT_RANGE_SIZE).Select(port => new Uri($"http://127.0.0.1:{port}/{ROOT_PATH}"));

    /// <summary>
    /// Normalizes a device UUID for comparison, as the UUID in the eSCL capabilities XML is sometimes prefixed with
    /// "urn:uuid:" while the mDNS TXT record is not.
    /// </summary>
    public static string NormalizeUuid(string uuid)
    {
        const string urnPrefix = "urn:uuid:";
        if (uuid.StartsWith(urnPrefix, StringComparison.OrdinalIgnoreCase))
        {
            uuid = uuid.Substring(urnPrefix.Length);
        }
        return uuid.ToLowerInvariant();
    }

    public static ScanDevice CreateScanDevice(IppUsbEsclEndpoint endpoint)
    {
        var caps = endpoint.Capabilities;
        string connectionUri = endpoint.Client.ConnectionUri;
        string id = string.IsNullOrEmpty(caps.Uuid) ? connectionUri : NormalizeUuid(caps.Uuid!);
        string model = caps.MakeAndModel ?? caps.Manufacturer ?? endpoint.Uri.Authority;
        string? iconUri = caps.IconUri;
        if (iconUri != null && !iconUri.StartsWith("http://") && !iconUri.StartsWith("https://"))
        {
            iconUri = null;
        }
        return new ScanDevice(Driver.Escl, id, $"{model} (USB)", iconUri, connectionUri);
    }

    public async Task<List<IppUsbEsclEndpoint>> ProbeEndpoints(EsclSecurityPolicy securityPolicy, ILogger logger,
        CancellationToken cancelToken)
    {
        var tasks = CandidateUris().Select(uri => ProbeEndpoint(uri, securityPolicy, logger, cancelToken));
        var results = await Task.WhenAll(tasks);
        return results.WhereNotNull().ToList();
    }

    public async Task<IppUsbEsclEndpoint?> ProbeEndpoint(Uri uri, EsclSecurityPolicy securityPolicy, ILogger logger,
        CancellationToken cancelToken)
    {
        var client = new EsclClient(uri)
        {
            SecurityPolicy = securityPolicy,
            Logger = logger,
            CancelToken = cancelToken
        };
        try
        {
            var caps = await client.GetCapabilities();
            logger.LogDebug("Found ipp-usb ESCL endpoint at {Uri}: {Model}, uuid {Uuid}", uri, caps.MakeAndModel,
                caps.Uuid);
            return new IppUsbEsclEndpoint(uri, client, caps);
        }
        catch (Exception ex)
        {
            // Expected case: nothing is listening on this port (or it isn't an eSCL service)
            logger.LogTrace(ex, "No ipp-usb ESCL endpoint at {Uri}", uri);
            return null;
        }
    }
}

internal record IppUsbEsclEndpoint(Uri Uri, EsclClient Client, EsclCapabilities Capabilities);
