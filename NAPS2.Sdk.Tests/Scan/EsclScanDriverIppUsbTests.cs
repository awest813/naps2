using System.Threading;
using NAPS2.Scan;
using NAPS2.Scan.Internal.Escl;
using Xunit;

namespace NAPS2.Sdk.Tests.Scan;

public class EsclScanDriverIppUsbTests : ContextualTests
{
    private const string CAPABILITIES_XML =
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <scan:ScannerCapabilities xmlns:scan="http://schemas.hp.com/imaging/escl/2011/05/03"
                                  xmlns:pwg="http://www.pwg.org/schemas/2010/12/sm">
            <pwg:Version>2.6</pwg:Version>
            <pwg:MakeAndModel>Canon imageFORMULA R10</pwg:MakeAndModel>
            <scan:Manufacturer>Canon</scan:Manufacturer>
            <scan:UUID>12345678-1234-1234-1234-123456789012</scan:UUID>
        </scan:ScannerCapabilities>
        """;

    [Fact]
    public async Task GetDevices_FindsIppUsbBridgedScanner()
    {
        if (!OperatingSystem.IsLinux())
        {
            // The ipp-usb probe only runs on Linux
            return;
        }
        // The driver probes the well-known ipp-usb port range starting at 60000, so the fake scanner must be at
        // exactly that port; skip if something else is already bound to it.
        if (!FakeEsclHttpServer.TryStart(60000, CAPABILITIES_XML, out var server))
        {
            return;
        }
        using var serverForDisposal = server;
        var driver = new EsclScanDriver(ScanningContext);
        var options = new ScanOptions
        {
            Driver = Driver.Escl,
            EsclOptions = { SearchTimeout = 2000 }
        };
        var devices = new List<ScanDevice>();

        await driver.GetDevices(options, CancellationToken.None, devices.Add);

        var device = Assert.Single(devices, d => d.Name == "Canon imageFORMULA R10 (USB)");
        Assert.Equal(Driver.Escl, device.Driver);
        Assert.Equal("12345678-1234-1234-1234-123456789012", device.ID);
        Assert.Equal("http://127.0.0.1:60000/eSCL", device.ConnectionUri);
    }

    [Fact]
    public async Task GetCaps_StaleConnectionUri_FallsBackToIppUsbProbe()
    {
        if (!OperatingSystem.IsLinux())
        {
            return;
        }
        // The scanner's ipp-usb port may change between sessions (e.g. after replugging); simulate that by giving
        // the device a stale ConnectionUri while the fake scanner is at a different port in the ipp-usb range.
        if (!FakeEsclHttpServer.TryStart(60001, CAPABILITIES_XML, out var server))
        {
            return;
        }
        using var serverForDisposal = server;
        int stalePort = GetUnusedPort();
        var driver = new EsclScanDriver(ScanningContext);
        var options = new ScanOptions
        {
            Driver = Driver.Escl,
            Device = new ScanDevice(Driver.Escl, "12345678-1234-1234-1234-123456789012",
                "Canon imageFORMULA R10 (USB)", null, $"http://127.0.0.1:{stalePort}/eSCL"),
            EsclOptions = { SearchTimeout = 2000 }
        };

        var caps = await driver.GetCaps(options, CancellationToken.None);

        Assert.Equal("Canon imageFORMULA R10", caps.MetadataCaps?.Model);
        Assert.Equal("Canon", caps.MetadataCaps?.Manufacturer);
    }

    private static int GetUnusedPort()
    {
        var listener = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, 0);
        listener.Start();
        int port = ((System.Net.IPEndPoint) listener.LocalEndpoint).Port;
        listener.Stop();
        return port;
    }
}
