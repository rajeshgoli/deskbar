import Darwin
import Foundation
import Network

struct NetworkInterfaceCounters: Equatable {
    var receivedBytes: UInt64
    var sentBytes: UInt64
    var errors: UInt64
    var linkSpeedBitsPerSecond: UInt64
}

/// Samples throughput and health of the primary physical interface. Path changes arrive from
/// `NWPathMonitor`; byte and error counters are read from the routing sysctl on each `sample()`.
@MainActor
final class NetworkMonitor {
    private struct PrimaryInterface: Equatable {
        let name: String
        let kind: NetworkInterfaceKind
    }

    private let pathMonitor = NWPathMonitor()
    private var isOnline = false
    private var hasReceivedPath = false
    private var primaryInterface: PrimaryInterface?
    private var previousCounters: NetworkInterfaceCounters?
    private var previousSampleTime: TimeInterval?
    private var previousInterfaceName: String?

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            let primary = Self.primaryInterface(
                from: path.availableInterfaces,
                isUsed: { path.usesInterfaceType($0) }
            )
            Task { @MainActor [weak self] in
                self?.hasReceivedPath = true
                self?.isOnline = isOnline
                self?.primaryInterface = primary
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "DeskBar.NetworkMonitor"))
    }

    deinit {
        pathMonitor.cancel()
    }

    func sample() -> NetworkSnapshot {
        guard hasReceivedPath else {
            return .empty
        }

        guard let primaryInterface, let counters = Self.readCounters(interfaceName: primaryInterface.name) else {
            resetRateBaseline()
            let (health, reasons) = NetworkSnapshot.health(
                isOnline: isOnline,
                interfaceKind: nil,
                linkSpeedBitsPerSecond: nil,
                newErrorCount: 0
            )
            return NetworkSnapshot(
                health: health,
                interfaceName: nil,
                interfaceKind: nil,
                linkSpeedBitsPerSecond: nil,
                downloadBytesPerSecond: nil,
                uploadBytesPerSecond: nil,
                newErrorCount: 0,
                healthReasons: reasons
            )
        }

        let now = ProcessInfo.processInfo.systemUptime
        var downloadRate: Double?
        var uploadRate: Double?
        var newErrors: UInt64 = 0

        if previousInterfaceName == primaryInterface.name,
           let previousCounters,
           let previousSampleTime,
           now > previousSampleTime {
            let elapsed = now - previousSampleTime
            downloadRate = Self.rate(current: counters.receivedBytes, previous: previousCounters.receivedBytes, elapsed: elapsed)
            uploadRate = Self.rate(current: counters.sentBytes, previous: previousCounters.sentBytes, elapsed: elapsed)
            newErrors = counters.errors >= previousCounters.errors ? counters.errors - previousCounters.errors : 0
        }

        previousCounters = counters
        previousSampleTime = now
        previousInterfaceName = primaryInterface.name

        let linkSpeed = counters.linkSpeedBitsPerSecond > 0 ? counters.linkSpeedBitsPerSecond : nil
        let (health, reasons) = NetworkSnapshot.health(
            isOnline: isOnline,
            interfaceKind: primaryInterface.kind,
            linkSpeedBitsPerSecond: linkSpeed,
            newErrorCount: newErrors
        )

        return NetworkSnapshot(
            health: health,
            interfaceName: primaryInterface.name,
            interfaceKind: primaryInterface.kind,
            linkSpeedBitsPerSecond: linkSpeed,
            downloadBytesPerSecond: downloadRate,
            uploadBytesPerSecond: uploadRate,
            newErrorCount: newErrors,
            healthReasons: reasons
        )
    }

    private func resetRateBaseline() {
        previousCounters = nil
        previousSampleTime = nil
        previousInterfaceName = nil
    }

    /// Picks the physical interface the path actually routes over, so a dormant Wi-Fi link on a
    /// dual-homed Mac is not sampled and a VPN tunnel (`utun`, type `.other`) reports the
    /// ethernet or Wi-Fi link it rides on.
    private nonisolated static func primaryInterface(
        from interfaces: [NWInterface],
        isUsed: (NWInterface.InterfaceType) -> Bool
    ) -> PrimaryInterface? {
        // `availableInterfaces` is preference-ordered; `usesInterfaceType` filters out adapters
        // the path is not routed over without overriding the user's service order.
        let physicalTypes: [NWInterface.InterfaceType] = [.wiredEthernet, .wifi, .cellular]
        let physicalInterfaces = interfaces.filter { physicalTypes.contains($0.type) }
        let physical = physicalInterfaces.first { isUsed($0.type) } ?? physicalInterfaces.first

        guard let interface = physical ?? interfaces.first(where: { $0.type != .loopback }) else {
            return nil
        }

        let kind: NetworkInterfaceKind
        switch interface.type {
        case .wiredEthernet:
            kind = .wiredEthernet
        case .wifi:
            kind = .wifi
        case .cellular:
            kind = .cellular
        default:
            kind = .other
        }

        return PrimaryInterface(name: interface.name, kind: kind)
    }

    nonisolated static func rate(current: UInt64, previous: UInt64, elapsed: TimeInterval) -> Double? {
        guard elapsed > 0, current >= previous else {
            return nil
        }

        return Double(current - previous) / elapsed
    }

    /// Reads 64-bit counters via `NET_RT_IFLIST2`; `getifaddrs` only exposes 32-bit byte counts,
    /// which wrap every 4 GiB.
    private static func readCounters(interfaceName: String) -> NetworkInterfaceCounters? {
        let interfaceIndex = if_nametoindex(interfaceName)
        guard interfaceIndex != 0 else {
            return nil
        }

        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else {
            return nil
        }

        return buffer.withUnsafeBytes { rawBuffer -> NetworkInterfaceCounters? in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = rawBuffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else {
                    return nil
                }

                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let message = rawBuffer.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if UInt32(message.ifm_index) == interfaceIndex {
                        let data = message.ifm_data
                        return NetworkInterfaceCounters(
                            receivedBytes: data.ifi_ibytes,
                            sentBytes: data.ifi_obytes,
                            errors: data.ifi_ierrors + data.ifi_oerrors,
                            linkSpeedBitsPerSecond: data.ifi_baudrate
                        )
                    }
                }

                offset += messageLength
            }

            return nil
        }
    }
}
