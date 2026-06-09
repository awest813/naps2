using System.Net;
using NAPS2.Scan.Internal;
using Xunit;

namespace NAPS2.Sdk.Tests.Scan;

public class LocalIPsHelperTests
{
    [Theory]
    [InlineData("192.168.1.9")]
    [InlineData("10.0.0.5")]
    public void ShouldExcludeByLocalIP_NonLoopbackLocalIp(string ip)
    {
        var localIPs = new HashSet<string> { ip };

        Assert.True(LocalIPsHelper.ShouldExcludeByLocalIP(ip, localIPs));
        Assert.True(LocalIPsHelper.ShouldExcludeByLocalIP(IPAddress.Parse(ip), localIPs));
    }

    [Theory]
    [InlineData("127.0.0.1")]
    [InlineData("::1")]
    public void ShouldExcludeByLocalIP_LoopbackIp(string ip)
    {
        var localIPs = new HashSet<string> { ip };

        Assert.False(LocalIPsHelper.ShouldExcludeByLocalIP(ip, localIPs));
        Assert.False(LocalIPsHelper.ShouldExcludeByLocalIP(IPAddress.Parse(ip), localIPs));
    }

    [Fact]
    public void ShouldExcludeByLocalIP_IpNotInLocalSet()
    {
        var localIPs = new HashSet<string> { "192.168.1.1" };

        Assert.False(LocalIPsHelper.ShouldExcludeByLocalIP("192.168.1.50", localIPs));
    }
}
