//
//  WarpModel.swift
//  Warp
//

import Foundation

public enum SpeedUnit: String, CaseIterable, Codable, Sendable {
    case mbps = "Mbps"
    case megabytesPerSec = "MB/s"

    public var displayName: String {
        switch self {
        case .mbps: return "Mbps (Megabits/s)"
        case .megabytesPerSec: return "MB/s (Megabytes/s)"
        }
    }

    public func convert(fromMbps mbps: Double) -> Double {
        switch self {
        case .mbps:
            return mbps
        case .megabytesPerSec:
            return mbps / 8.0
        }
    }

    public func format(mbps: Double) -> String {
        let value = convert(fromMbps: mbps)
        if value >= 100 {
            return String(format: "%.0f %@", value, rawValue)
        } else if value >= 10 {
            return String(format: "%.1f %@", value, rawValue)
        } else {
            return String(format: "%.2f %@", value, rawValue)
        }
    }

    public func formatValueOnly(mbps: Double) -> String {
        let value = convert(fromMbps: mbps)
        if value >= 100 {
            return String(format: "%.0f", value)
        } else if value >= 10 {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
}

public enum SpeedtestPhase: Equatable, Sendable {
    case idle
    case locating
    case pinging
    case downloading(currentMbps: Double)
    case uploading(currentMbps: Double)
    case completed
    case failed(String)

    public var label: String {
        switch self {
        case .idle: return "Ready"
        case .locating: return "Finding best server…"
        case .pinging: return "Testing ping…"
        case .downloading: return "Testing download…"
        case .uploading: return "Testing upload…"
        case .completed: return "Test finished"
        case .failed(let err): return "Error: \(err)"
        }
    }

    public var isTesting: Bool {
        switch self {
        case .locating, .pinging, .downloading, .uploading:
            return true
        default:
            return false
        }
    }
}

public struct SpeedtestTelemetry: Codable, Equatable, Sendable {
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let pingMs: Double
    public let jitterMs: Double
    public let responsivenessRPM: Double
    public let serverName: String
    public let serverSponsor: String
    public let serverCountry: String
    public let serverDistanceKm: Double
    public let serverHost: String
    public let clientIP: String
    public let clientISP: String
    public let clientCountry: String
    public let bytesReceived: Int64
    public let bytesSent: Int64
    public let timestamp: Date
    public let shareURL: URL?
    public let interfaceType: String
    public let protocolName: String
    public let workingLatencyMs: Double
    public let tcpHandshakeMs: Double
    public let tlsHandshakeMs: Double

    public init(
        downloadMbps: Double,
        uploadMbps: Double,
        pingMs: Double,
        jitterMs: Double = 0.0,
        responsivenessRPM: Double = 0.0,
        serverName: String,
        serverSponsor: String,
        serverCountry: String,
        serverDistanceKm: Double,
        serverHost: String,
        clientIP: String,
        clientISP: String,
        clientCountry: String,
        bytesReceived: Int64,
        bytesSent: Int64,
        timestamp: Date = Date(),
        shareURL: URL? = nil,
        interfaceType: String = "Wi-Fi",
        protocolName: String = "HTTP/2",
        workingLatencyMs: Double = 0.0,
        tcpHandshakeMs: Double = 0.0,
        tlsHandshakeMs: Double = 0.0
    ) {
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.pingMs = pingMs
        self.jitterMs = jitterMs
        self.responsivenessRPM = responsivenessRPM
        self.serverName = serverName
        self.serverSponsor = serverSponsor
        self.serverCountry = serverCountry
        self.serverDistanceKm = serverDistanceKm
        self.serverHost = serverHost
        self.clientIP = clientIP
        self.clientISP = clientISP
        self.clientCountry = clientCountry
        self.bytesReceived = bytesReceived
        self.bytesSent = bytesSent
        self.timestamp = timestamp
        self.shareURL = shareURL
        self.interfaceType = interfaceType
        self.protocolName = protocolName
        self.workingLatencyMs = workingLatencyMs
        self.tcpHandshakeMs = tcpHandshakeMs
        self.tlsHandshakeMs = tlsHandshakeMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.downloadMbps = try container.decode(Double.self, forKey: .downloadMbps)
        self.uploadMbps = try container.decode(Double.self, forKey: .uploadMbps)
        self.pingMs = try container.decode(Double.self, forKey: .pingMs)
        self.jitterMs = try container.decodeIfPresent(Double.self, forKey: .jitterMs) ?? 0.0
        self.responsivenessRPM = try container.decodeIfPresent(Double.self, forKey: .responsivenessRPM) ?? 0.0
        self.serverName = try container.decode(String.self, forKey: .serverName)
        self.serverSponsor = try container.decode(String.self, forKey: .serverSponsor)
        self.serverCountry = try container.decode(String.self, forKey: .serverCountry)
        self.serverDistanceKm = try container.decode(Double.self, forKey: .serverDistanceKm)
        self.serverHost = try container.decode(String.self, forKey: .serverHost)
        self.clientIP = try container.decode(String.self, forKey: .clientIP)
        self.clientISP = try container.decode(String.self, forKey: .clientISP)
        self.clientCountry = try container.decode(String.self, forKey: .clientCountry)
        self.bytesReceived = try container.decode(Int64.self, forKey: .bytesReceived)
        self.bytesSent = try container.decode(Int64.self, forKey: .bytesSent)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.shareURL = try container.decodeIfPresent(URL.self, forKey: .shareURL)
        self.interfaceType = try container.decodeIfPresent(String.self, forKey: .interfaceType) ?? "Wi-Fi"
        self.protocolName = try container.decodeIfPresent(String.self, forKey: .protocolName) ?? "HTTP/2"
        self.workingLatencyMs = try container.decodeIfPresent(Double.self, forKey: .workingLatencyMs) ?? 0.0
        self.tcpHandshakeMs = try container.decodeIfPresent(Double.self, forKey: .tcpHandshakeMs) ?? 0.0
        self.tlsHandshakeMs = try container.decodeIfPresent(Double.self, forKey: .tlsHandshakeMs) ?? 0.0
    }

    public static let placeholder = SpeedtestTelemetry(
        downloadMbps: 0,
        uploadMbps: 0,
        pingMs: 0,
        jitterMs: 0,
        responsivenessRPM: 0,
        serverName: "—",
        serverSponsor: "—",
        serverCountry: "—",
        serverDistanceKm: 0,
        serverHost: "—",
        clientIP: "—",
        clientISP: "—",
        clientCountry: "—",
        bytesReceived: 0,
        bytesSent: 0,
        timestamp: Date()
    )
}

public struct WarpHistoryItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public let timestamp: Date
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let pingMs: Double
    public let serverName: String
    public let clientISP: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        downloadMbps: Double,
        uploadMbps: Double,
        pingMs: Double,
        serverName: String,
        clientISP: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
        self.pingMs = pingMs
        self.serverName = serverName
        self.clientISP = clientISP
    }

    public init(telemetry: SpeedtestTelemetry) {
        self.id = UUID()
        self.timestamp = telemetry.timestamp
        self.downloadMbps = telemetry.downloadMbps
        self.uploadMbps = telemetry.uploadMbps
        self.pingMs = telemetry.pingMs
        self.serverName = telemetry.serverName
        self.clientISP = telemetry.clientISP
    }
}

struct NetworkQualityOutput: Decodable {
    struct OtherInfo: Decodable {
        let interfaceType: [String: Int]?
        let protocolsSeen: [String: Int]?

        enum CodingKeys: String, CodingKey {
            case interfaceType = "interface-type"
            case protocolsSeen = "protocols_seen"
        }
    }

    let dlThroughput: Double?
    let ulThroughput: Double?
    let baseRtt: Double?
    let responsiveness: Double?
    let dlResponsiveness: Double?
    let ulResponsiveness: Double?
    let dlBytesTransferred: Int64?
    let ulBytesTransferred: Int64?
    let interfaceName: String?
    let testEndpoint: String?
    let osVersion: String?
    let startDate: String?
    let endDate: String?
    let other: OtherInfo?
    let ilTcpHandshake: [Double]?
    let ilTlsHandshake: [Double]?
    let ludForeignDlH2: [Double]?
    let ludForeignUlH2: [Double]?
    let ludForeignH2: [Double]?

    enum CodingKeys: String, CodingKey {
        case dlThroughput = "dl_throughput"
        case ulThroughput = "ul_throughput"
        case baseRtt = "base_rtt"
        case responsiveness
        case dlResponsiveness = "dl_responsiveness"
        case ulResponsiveness = "ul_responsiveness"
        case dlBytesTransferred = "dl_bytes_transferred"
        case ulBytesTransferred = "ul_bytes_transferred"
        case interfaceName = "interface_name"
        case testEndpoint = "test_endpoint"
        case osVersion = "os_version"
        case startDate = "start_date"
        case endDate = "end_date"
        case other
        case ilTcpHandshake = "il_tcp_handshake_443"
        case ilTlsHandshake = "il_tls_handshake"
        case ludForeignDlH2 = "lud_foreign_dl_h2_req_resp"
        case ludForeignUlH2 = "lud_foreign_ul_h2_req_resp"
        case ludForeignH2 = "lud_foreign_h2_req_resp"
    }

    func toTelemetry() -> SpeedtestTelemetry {
        // networkQuality reports throughput in bits per second. Convert to Megabits per second (10^6).
        let dlMbps = (dlThroughput ?? 0.0) / 1_000_000.0
        let ulMbps = (ulThroughput ?? 0.0) / 1_000_000.0
        let ping = baseRtt ?? 0.0
        let rpm = responsiveness ?? dlResponsiveness ?? ulResponsiveness ?? 0.0
        let endpoint = testEndpoint ?? "Apple CDN"
        let iface = interfaceName ?? "en0"

        let resolvedIfaceType: String
        if let typeKey = other?.interfaceType?.keys.first {
            resolvedIfaceType = typeKey.lowercased() == "wired" ? "Ethernet" : (typeKey.lowercased() == "wifi" ? "Wi-Fi" : typeKey.capitalized)
        } else {
            resolvedIfaceType = "Wi-Fi"
        }

        let proto = other?.protocolsSeen?.keys.first?.uppercased() ?? "HTTP/2"

        func average(_ arr: [Double]?) -> Double {
            guard let arr, !arr.isEmpty else { return 0.0 }
            return arr.reduce(0.0, +) / Double(arr.count)
        }

        let loadedLatency = average(ludForeignDlH2 ?? ludForeignUlH2 ?? ludForeignH2)
        let tcpMs = average(ilTcpHandshake)
        let tlsMs = average(ilTlsHandshake)

        return SpeedtestTelemetry(
            downloadMbps: dlMbps,
            uploadMbps: ulMbps,
            pingMs: ping,
            jitterMs: 0.0,
            responsivenessRPM: rpm,
            serverName: endpoint,
            serverSponsor: "Apple Edge CDN",
            serverCountry: "macOS Native",
            serverDistanceKm: 0.0,
            serverHost: endpoint,
            clientIP: iface,
            clientISP: "\(resolvedIfaceType) (\(iface))",
            clientCountry: "",
            bytesReceived: dlBytesTransferred ?? 0,
            bytesSent: ulBytesTransferred ?? 0,
            timestamp: Date(),
            shareURL: nil,
            interfaceType: resolvedIfaceType,
            protocolName: proto,
            workingLatencyMs: loadedLatency,
            tcpHandshakeMs: tcpMs,
            tlsHandshakeMs: tlsMs
        )
    }
}
