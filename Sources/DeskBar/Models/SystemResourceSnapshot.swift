import Foundation

enum SystemResourceMetric: CaseIterable {
    case memory
    case cpu
    case gpu
    case network
}

enum MemoryPressureLevel: String, Equatable {
    case normal
    case warning
    case critical
    case unknown

    var displayName: String {
        switch self {
        case .normal:
            return "Normal"
        case .warning:
            return "Warning"
        case .critical:
            return "Critical"
        case .unknown:
            return "Unknown"
        }
    }
}

enum NetworkInterfaceKind: Equatable {
    case wiredEthernet
    case wifi
    case cellular
    case other

    var displayName: String {
        switch self {
        case .wiredEthernet:
            return "Ethernet"
        case .wifi:
            return "Wi-Fi"
        case .cellular:
            return "Cellular"
        case .other:
            return "Other"
        }
    }
}

enum NetworkHealth: Equatable {
    /// Primary path is wired ethernet at gigabit or better with no new interface errors.
    case good
    /// Online, but not over healthy ethernet: Wi-Fi fallback, a sub-gigabit link, or rising errors.
    case degraded
    case offline
    case unknown
}

struct NetworkSnapshot: Equatable {
    var health: NetworkHealth
    var interfaceName: String?
    var interfaceKind: NetworkInterfaceKind?
    var linkSpeedBitsPerSecond: UInt64?
    var downloadBytesPerSecond: Double?
    var uploadBytesPerSecond: Double?
    var newErrorCount: UInt64
    var healthReasons: [String]

    static let empty = NetworkSnapshot(
        health: .unknown,
        interfaceName: nil,
        interfaceKind: nil,
        linkSpeedBitsPerSecond: nil,
        downloadBytesPerSecond: nil,
        uploadBytesPerSecond: nil,
        newErrorCount: 0,
        healthReasons: []
    )

    static let gigabitBitsPerSecond: UInt64 = 1_000_000_000

    static func health(
        isOnline: Bool,
        interfaceKind: NetworkInterfaceKind?,
        linkSpeedBitsPerSecond: UInt64?,
        newErrorCount: UInt64
    ) -> (NetworkHealth, [String]) {
        guard isOnline, let interfaceKind else {
            return (.offline, ["No network connection"])
        }

        var reasons: [String] = []
        if interfaceKind != .wiredEthernet {
            reasons.append("Using \(interfaceKind.displayName), not Ethernet")
        } else if let linkSpeedBitsPerSecond, linkSpeedBitsPerSecond > 0,
                  linkSpeedBitsPerSecond < gigabitBitsPerSecond {
            reasons.append("Link negotiated below 1 Gbps (check cable)")
        }

        if newErrorCount > 0 {
            reasons.append("\(newErrorCount) new interface errors")
        }

        return (reasons.isEmpty ? .good : .degraded, reasons)
    }
}

struct SystemResourceSnapshot: Equatable {
    var memoryPressureLevel: MemoryPressureLevel
    var memoryPressurePercent: Double?
    var memoryFreePercent: Double?
    var memoryUsedBytes: UInt64?
    var memoryTotalBytes: UInt64?
    var cpuPercent: Double?
    var gpuPercent: Double?
    var network: NetworkSnapshot = .empty

    static let empty = SystemResourceSnapshot(
        memoryPressureLevel: .unknown,
        memoryPressurePercent: nil,
        memoryFreePercent: nil,
        memoryUsedBytes: nil,
        memoryTotalBytes: nil,
        cpuPercent: nil,
        gpuPercent: nil
    )

    var memoryUsedPercent: Double? {
        guard let memoryUsedBytes, let memoryTotalBytes, memoryTotalBytes > 0 else {
            return memoryPressurePercent
        }

        return min(max((Double(memoryUsedBytes) / Double(memoryTotalBytes)) * 100, 0), 100)
    }
}
