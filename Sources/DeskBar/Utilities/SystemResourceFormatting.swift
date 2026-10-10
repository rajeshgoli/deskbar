import Foundation

enum SystemResourceMetricSeverity {
    case normal
    case warning
    case critical
    case unknown
}

/// Text and severity shared by the taskbar widget and the menu bar status item.
enum SystemResourceFormatting {
    static func percentString(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }

        return "\(Int(value.rounded()))%"
    }

    static func memoryAmountString(_ bytes: UInt64, includesUnit: Bool) -> String {
        let gibibytes = Double(bytes) / 1_073_741_824
        let suffix = includesUnit ? "G" : ""
        if gibibytes >= 10 {
            return "\(Int(gibibytes.rounded()))\(suffix)"
        }

        return String(format: "%.1f%@", gibibytes, suffix)
    }

    static func memoryValueString(for snapshot: SystemResourceSnapshot) -> String {
        guard let usedBytes = snapshot.memoryUsedBytes,
              let totalBytes = snapshot.memoryTotalBytes else {
            return percentString(snapshot.memoryUsedPercent)
        }

        return "\(memoryAmountString(usedBytes, includesUnit: false))/\(memoryAmountString(totalBytes, includesUnit: true))"
    }

    static func memoryTooltip(for snapshot: SystemResourceSnapshot) -> String {
        let used = memoryValueString(for: snapshot)
        let pressure = percentString(snapshot.memoryPressurePercent)
        let free = snapshot.memoryFreePercent.map { "\(Int($0.rounded()))% free" } ?? "free memory unavailable"
        return "Memory: \(used). Pressure: \(snapshot.memoryPressureLevel.displayName), \(pressure) pressure, \(free)."
    }

    /// Compact byte rate that never exceeds four characters, e.g. "0K", "34K", "1.2M", "118M".
    static func rateString(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else {
            return "--"
        }

        let units = ["K", "M", "G"]
        var value = max(bytesPerSecond, 0) / 1_000
        var unitIndex = 0
        while value >= 999.5, unitIndex < units.count - 1 {
            value /= 1_000
            unitIndex += 1
        }

        if value < 9.95, unitIndex > 0 {
            return String(format: "%.1f%@", value, units[unitIndex])
        }

        return "\(Int(value.rounded()))\(units[unitIndex])"
    }

    static func networkValueString(for network: NetworkSnapshot) -> String {
        "↓\(rateString(network.downloadBytesPerSecond)) ↑\(rateString(network.uploadBytesPerSecond))"
    }

    static func linkSpeedString(_ bitsPerSecond: UInt64?) -> String? {
        guard let bitsPerSecond, bitsPerSecond > 0 else {
            return nil
        }

        if bitsPerSecond >= 1_000_000_000 {
            let gigabits = Double(bitsPerSecond) / 1_000_000_000
            return gigabits == gigabits.rounded()
                ? "\(Int(gigabits)) Gbps"
                : String(format: "%.1f Gbps", gigabits)
        }

        return "\(bitsPerSecond / 1_000_000) Mbps"
    }

    static func networkStatusString(for network: NetworkSnapshot) -> String {
        switch network.health {
        case .unknown:
            return "Network: checking…"
        case .offline:
            return "Network: offline"
        case .good, .degraded:
            var parts = [network.interfaceKind?.displayName ?? "Connected"]
            if let interfaceName = network.interfaceName {
                parts[0] += " (\(interfaceName))"
            }
            if let linkSpeed = linkSpeedString(network.linkSpeedBitsPerSecond) {
                parts.append(linkSpeed)
            }
            parts.append(network.health == .good ? "OK" : network.healthReasons.joined(separator: "; "))
            return "Network: " + parts.joined(separator: ", ")
        }
    }

    static func networkTooltip(for network: NetworkSnapshot) -> String {
        "\(networkStatusString(for: network)). Download \(rateString(network.downloadBytesPerSecond))B/s, upload \(rateString(network.uploadBytesPerSecond))B/s."
    }

    static func severity(
        percent: Double?,
        pressureLevel: MemoryPressureLevel? = nil
    ) -> SystemResourceMetricSeverity {
        if pressureLevel == .critical {
            return .critical
        }

        if pressureLevel == .warning {
            return .warning
        }

        guard let percent else {
            return .unknown
        }

        if percent >= 90 {
            return .critical
        }

        if percent >= 75 {
            return .warning
        }

        return .normal
    }

    static func severity(for network: NetworkSnapshot) -> SystemResourceMetricSeverity {
        switch network.health {
        case .good:
            return .normal
        case .degraded:
            return .warning
        case .offline:
            return .critical
        case .unknown:
            return .unknown
        }
    }
}
