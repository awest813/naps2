namespace NAPS2.Sdk.ScannerTests;

public class HowToRunScannerTests
{
    // 1. Print out the NAPS2 test page (naps2_test_page.pdf) and put it in your scanner.
    
    // 2. Set to "" to use the first scanner device, otherwise a substring of the scanner name (e.g. "Canon").
    public const string SCANNER_NAME = "";
    
    // 3. Start debugging the test you want to run.
    //
    // Linux / Ubuntu validation checklist:
    // - Native environment checks:
    //   - lsusb
    //   - sane-find-scanner
    //   - scanimage -L
    // - Flatpak checks:
    //   - Ensure USB access is granted (manifest uses --device=all)
    //   - Verify the same scanner appears in device discovery
    // - Functional checks:
    //   - Discovery
    //   - Feeder scan
    //   - Duplex scan (if hardware supports it)
    //   - Reconnect scanner and verify rediscovery
    //
    // Canon imageFORMULA R10 note:
    // The R10 can be used on Linux via ipp-usb (a USB-to-IPP bridge daemon).
    // Install ipp-usb (`apt install ipp-usb`), ensure it is running, and reconnect the scanner.
    // The device should then appear via the SANE airscan backend or the ESCL driver at a loopback address.
    // If it still does not appear, confirm with `scanimage -L` that airscan/escl lists it.
} 