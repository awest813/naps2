using System.Net;
using System.Net.Sockets;
using System.Text;

namespace NAPS2.Sdk.Tests.Scan;

/// <summary>
/// A minimal HTTP server that responds to every request with the given XML, simulating the eSCL endpoint that
/// ipp-usb exposes on localhost for a bridged USB scanner.
/// </summary>
internal class FakeEsclHttpServer : IDisposable
{
    private readonly TcpListener _listener;
    private readonly string _responseBody;

    public static bool TryStart(int port, string responseBody, out FakeEsclHttpServer? server)
    {
        try
        {
            server = new FakeEsclHttpServer(responseBody, port);
            return true;
        }
        catch (SocketException)
        {
            server = null;
            return false;
        }
    }

    public FakeEsclHttpServer(string responseBody, int port = 0)
    {
        _responseBody = responseBody;
        _listener = new TcpListener(IPAddress.Loopback, port);
        _listener.Start();
        Port = ((IPEndPoint) _listener.LocalEndpoint).Port;
        Task.Run(AcceptLoop);
    }

    public int Port { get; }

    private async Task AcceptLoop()
    {
        while (true)
        {
            TcpClient client;
            try
            {
                client = await _listener.AcceptTcpClientAsync();
            }
            catch (Exception)
            {
                return;
            }
            _ = Task.Run(async () =>
            {
                using var clientForDisposal = client;
                var stream = client.GetStream();
                // Read the request headers (we don't need to parse them)
                var buffer = new byte[65536];
                int bytesRead = await stream.ReadAsync(buffer, 0, buffer.Length);
                if (bytesRead == 0) return;
                var body = Encoding.UTF8.GetBytes(_responseBody);
                var headers = Encoding.ASCII.GetBytes(
                    "HTTP/1.1 200 OK\r\n" +
                    "Content-Type: text/xml\r\n" +
                    $"Content-Length: {body.Length}\r\n" +
                    "Connection: close\r\n" +
                    "\r\n");
                await stream.WriteAsync(headers, 0, headers.Length);
                await stream.WriteAsync(body, 0, body.Length);
            });
        }
    }

    public void Dispose()
    {
        _listener.Stop();
    }
}
