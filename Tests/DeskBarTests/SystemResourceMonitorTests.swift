import Darwin
import Testing
@testable import DeskBar

@Test
func activityMonitorMemoryUsedExcludesFileBackedCache() {
    var stats = vm_statistics64()
    stats.internal_page_count = 100
    stats.external_page_count = 50
    stats.wire_count = 20
    stats.compressor_page_count = 30

    let usedBytes = SystemResourceMonitor.activityMonitorUsedMemoryBytes(
        stats: stats,
        pageSize: 4,
        totalBytes: nil
    )

    #expect(usedBytes == 600)
}

@Test
func networkHealthIsGoodOnlyForGigabitEthernetWithoutNewErrors() {
    let good = NetworkSnapshot.health(
        isOnline: true,
        interfaceKind: .wiredEthernet,
        linkSpeedBitsPerSecond: 1_000_000_000,
        newErrorCount: 0
    )
    #expect(good.0 == .good)
    #expect(good.1.isEmpty)

    let tenGig = NetworkSnapshot.health(
        isOnline: true,
        interfaceKind: .wiredEthernet,
        linkSpeedBitsPerSecond: 10_000_000_000,
        newErrorCount: 0
    )
    #expect(tenGig.0 == .good)

    let slowLink = NetworkSnapshot.health(
        isOnline: true,
        interfaceKind: .wiredEthernet,
        linkSpeedBitsPerSecond: 100_000_000,
        newErrorCount: 0
    )
    #expect(slowLink.0 == .degraded)

    let errors = NetworkSnapshot.health(
        isOnline: true,
        interfaceKind: .wiredEthernet,
        linkSpeedBitsPerSecond: 1_000_000_000,
        newErrorCount: 3
    )
    #expect(errors.0 == .degraded)
    #expect(errors.1 == ["3 new interface errors"])

    let wifi = NetworkSnapshot.health(
        isOnline: true,
        interfaceKind: .wifi,
        linkSpeedBitsPerSecond: 1_200_000_000,
        newErrorCount: 0
    )
    #expect(wifi.0 == .degraded)
    #expect(wifi.1 == ["Using Wi-Fi, not Ethernet"])

    #expect(NetworkSnapshot.health(
        isOnline: false,
        interfaceKind: .wiredEthernet,
        linkSpeedBitsPerSecond: 1_000_000_000,
        newErrorCount: 0
    ).0 == .offline)
    #expect(NetworkSnapshot.health(
        isOnline: true,
        interfaceKind: nil,
        linkSpeedBitsPerSecond: nil,
        newErrorCount: 0
    ).0 == .offline)
}

@Test
func networkRateIgnoresCounterResets() {
    #expect(NetworkMonitor.rate(current: 3_000, previous: 1_000, elapsed: 2) == 1_000)
    #expect(NetworkMonitor.rate(current: 500, previous: 1_000, elapsed: 2) == nil)
    #expect(NetworkMonitor.rate(current: 2_000, previous: 1_000, elapsed: 0) == nil)
}

@Test
func networkRateStringStaysCompact() {
    #expect(SystemResourceFormatting.rateString(nil) == "--")
    #expect(SystemResourceFormatting.rateString(0) == "0K")
    #expect(SystemResourceFormatting.rateString(34_200) == "34K")
    #expect(SystemResourceFormatting.rateString(999_400) == "999K")
    #expect(SystemResourceFormatting.rateString(999_600) == "1.0M")
    #expect(SystemResourceFormatting.rateString(1_240_000) == "1.2M")
    #expect(SystemResourceFormatting.rateString(118_000_000) == "118M")
    #expect(SystemResourceFormatting.rateString(1_150_000_000) == "1.1G")
    for value in stride(from: 0.0, through: 5_000_000_000, by: 7_777_777) {
        #expect(SystemResourceFormatting.rateString(value).count <= 4)
    }
}

@Test
func networkStatusDescribesLinkAndProblems() {
    var network = NetworkSnapshot.empty
    network.health = .good
    network.interfaceName = "en0"
    network.interfaceKind = .wiredEthernet
    network.linkSpeedBitsPerSecond = 1_000_000_000
    #expect(SystemResourceFormatting.networkStatusString(for: network) == "Network: Ethernet (en0), 1 Gbps, OK")

    network.health = .degraded
    network.linkSpeedBitsPerSecond = 100_000_000
    network.healthReasons = ["Link negotiated below 1 Gbps (check cable)"]
    #expect(SystemResourceFormatting.networkStatusString(for: network) == "Network: Ethernet (en0), 100 Mbps, Link negotiated below 1 Gbps (check cable)")

    #expect(SystemResourceFormatting.linkSpeedString(2_500_000_000) == "2.5 Gbps")
    #expect(SystemResourceFormatting.severity(for: NetworkSnapshot.empty) == .unknown)
}

@Test
func activityMonitorNetworkPaneUsesCommandFive() {
    #expect(ActivityMonitorLauncher.navigationScript(for: .network).contains("keystroke \"5\" using command down"))
}
