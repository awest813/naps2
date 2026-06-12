using System.Net;
using System.Net.Sockets;
using System.Threading;
using Microsoft.Extensions.Logging.Abstractions;
using NAPS2.Escl;
using NAPS2.Escl.Client;
using NAPS2.Scan;
using NAPS2.Scan.Internal.Escl;
using Xunit;

namespace NAPS2.Sdk.Tests.Scan;

public class IppUsbEsclLocatorTests
{
    private const string CAPABILITIES_XML =
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <scan:ScannerCapabilities xmlns:scan="http://schemas.hp.com/imaging/escl/2011/05/03"
                                  xmlns:pwg="http://www.pwg.org/schemas/2010/12/sm">
            <pwg:Version>2.6</pwg:Version>
            <pwg:MakeAndModel>Canon imageFORMULA R10</pwg:MakeAndModel>
            <scan:Manufacturer>Canon</scan:Manufacturer>
            <scan:UUID>urn:uuid:12345678-1234-1234-1234-123456789012</scan:UUID>
        </scan:ScannerCapabilities>
        """;

    [Theory]
    [InlineData("urn:uuid:ABC-123", "abc-123")]
    [InlineData("URN:UUID:abc-123", "abc-123")]
    [InlineData("ABC-123", "abc-123")]
    [InlineData("abc-123", "abc-123")]
    public void NormalizeUuid(string input, string expected)
    {
        Assert.Equal(expected, IppUsbEsclLocator.NormalizeUuid(input));
    }

    [Fact]
    public void CandidateUris_AreLoopbackIppUsbPorts()
    {
        var uris = IppUsbEsclLocator.CandidateUris().ToList();

        Assert.NotEmpty(uris);
        Assert.Equal("http://127.0.0.1:60000/eSCL", uris[0].ToString().TrimEnd('/'));
        Assert.All(uris, uri => Assert.Equal("127.0.0.1", uri.Host));
        Assert.All(uris, uri => Assert.InRange(uri.Port, 60000, 65535));
    }

    [Fact]
    public void CreateScanDevice_WithUuid()
    {
        var endpoint = CreateEndpoint(60000, new EsclCapabilities
        {
            MakeAndModel = "Canon imageFORMULA R10",
            Manufacturer = "Canon",
            Uuid = "urn:uuid:ABC-123"
        });

        var device = IppUsbEsclLocator.CreateScanDevice(endpoint);

        Assert.Equal(Driver.Escl, device.Driver);
        Assert.Equal("abc-123", device.ID);
        Assert.Equal("Canon imageFORMULA R10 (USB)", device.Name);
        Assert.Equal("http://127.0.0.1:60000/eSCL", device.ConnectionUri);
        Assert.Null(device.IconUri);
    }

    [Fact]
    public void CreateScanDevice_WithoutUuid_UsesConnectionUriAsId()
    {
        var endpoint = CreateEndpoint(60001, new EsclCapabilities
        {
            MakeAndModel = "Canon imageFORMULA R10"
        });

        var device = IppUsbEsclLocator.CreateScanDevice(endpoint);

        Assert.Equal("http://127.0.0.1:60001/eSCL", device.ID);
        Assert.Equal("http://127.0.0.1:60001/eSCL", device.ConnectionUri);
    }

    [Fact]
    public void CreateScanDevice_WithoutModel_UsesManufacturerThenAuthority()
    {
        var withManufacturer = CreateEndpoint(60000, new EsclCapabilities { Manufacturer = "Canon" });
        Assert.Equal("Canon (USB)", IppUsbEsclLocator.CreateScanDevice(withManufacturer).Name);

        var withoutAnything = CreateEndpoint(60000, new EsclCapabilities());
        Assert.Equal("127.0.0.1:60000 (USB)", IppUsbEsclLocator.CreateScanDevice(withoutAnything).Name);
    }

    [Fact]
    public void CreateScanDevice_NonHttpIconUriIsIgnored()
    {
        var endpoint = CreateEndpoint(60000, new EsclCapabilities
        {
            MakeAndModel = "Canon imageFORMULA R10",
            IconUri = "/icon.png"
        });

        Assert.Null(IppUsbEsclLocator.CreateScanDevice(endpoint).IconUri);
    }

    [Fact]
    public async Task ProbeEndpoint_RespondingServer_ReturnsEndpointWithCaps()
    {
        using var server = new FakeEsclHttpServer(CAPABILITIES_XML);
        var uri = new Uri($"http://127.0.0.1:{server.Port}/eSCL");

        var endpoint = await new IppUsbEsclLocator().ProbeEndpoint(
            uri, EsclSecurityPolicy.None, NullLogger.Instance, CancellationToken.None);

        Assert.NotNull(endpoint);
        Assert.Equal("Canon imageFORMULA R10", endpoint!.Capabilities.MakeAndModel);
        Assert.Equal("urn:uuid:12345678-1234-1234-1234-123456789012", endpoint.Capabilities.Uuid);

        var device = IppUsbEsclLocator.CreateScanDevice(endpoint);
        Assert.Equal("12345678-1234-1234-1234-123456789012", device.ID);
        Assert.Equal("Canon imageFORMULA R10 (USB)", device.Name);
        Assert.Equal($"http://127.0.0.1:{server.Port}/eSCL", device.ConnectionUri);
    }

    [Fact]
    public async Task ProbeEndpoint_NoServer_ReturnsNull()
    {
        // Find a port with nothing listening by binding and immediately closing it
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int unusedPort = ((IPEndPoint) listener.LocalEndpoint).Port;
        listener.Stop();
        var uri = new Uri($"http://127.0.0.1:{unusedPort}/eSCL");

        var endpoint = await new IppUsbEsclLocator().ProbeEndpoint(
            uri, EsclSecurityPolicy.None, NullLogger.Instance, CancellationToken.None);

        Assert.Null(endpoint);
    }

    private static IppUsbEsclEndpoint CreateEndpoint(int port, EsclCapabilities caps)
    {
        var uri = new Uri($"http://127.0.0.1:{port}/eSCL");
        return new IppUsbEsclEndpoint(uri, new EsclClient(uri), caps);
    }
}
