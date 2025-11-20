//
//  SignalMappingModels.swift
//  Meshtastic
//
//  Signal mapping data models for RF coverage testing
//

import Foundation
import CoreLocation

// MARK: - Mapping Point

/// Represents a single signal measurement point
struct MappingPoint: Codable, Identifiable, Hashable {
	let id: UUID
	let timestamp: Date
	let latitude: Double
	let longitude: Double
	let altitude: Double?
	let horizontalAccuracy: Double
	let snr: Float
	let rssi: Int32
	let channel: UInt32
	let responderNodeNum: Int64 // Which node responded
	let responseTime: TimeInterval? // Time to receive ACK
	let success: Bool // Whether ACK was received

	init(
		id: UUID = UUID(),
		timestamp: Date = Date(),
		latitude: Double,
		longitude: Double,
		altitude: Double? = nil,
		horizontalAccuracy: Double,
		snr: Float,
		rssi: Int32,
		channel: UInt32,
		responderNodeNum: Int64,
		responseTime: TimeInterval? = nil,
		success: Bool
	) {
		self.id = id
		self.timestamp = timestamp
		self.latitude = latitude
		self.longitude = longitude
		self.altitude = altitude
		self.horizontalAccuracy = horizontalAccuracy
		self.snr = snr
		self.rssi = rssi
		self.channel = channel
		self.responderNodeNum = responderNodeNum
		self.responseTime = responseTime
		self.success = success
	}

	/// Convert to CLLocationCoordinate2D for MapKit
	var coordinate: CLLocationCoordinate2D {
		CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
	}

	/// Signal quality level (0-4)
	var signalQuality: Int {
		if snr >= 10 { return 4 } // Excellent
		if snr >= 5 { return 3 }  // Good
		if snr >= 0 { return 2 }  // Fair
		if snr >= -5 { return 1 } // Poor
		return 0 // Very poor
	}
}

// MARK: - Mapping Session

/// Represents a complete signal mapping session
struct MappingSession: Codable, Identifiable, Hashable {
	let id: UUID
	let name: String
	let createdDate: Date
	var lastUpdated: Date
	let targetNodeNum: Int64 // Node to ping for signal testing
	let targetNodeName: String // Name of target node for logging
	var points: [MappingPoint]
	var probeInterval: TimeInterval // Seconds between probes
	var isActive: Bool

	init(
		id: UUID = UUID(),
		name: String,
		createdDate: Date = Date(),
		lastUpdated: Date = Date(),
		targetNodeNum: Int64,
		targetNodeName: String,
		points: [MappingPoint] = [],
		probeInterval: TimeInterval = 10.0,
		isActive: Bool = false
	) {
		self.id = id
		self.name = name
		self.createdDate = createdDate
		self.lastUpdated = lastUpdated
		self.targetNodeNum = targetNodeNum
		self.targetNodeName = targetNodeName
		self.points = points
		self.probeInterval = probeInterval
		self.isActive = isActive
	}

	// MARK: - Statistics

	var totalPoints: Int {
		points.count
	}

	var successfulPoints: Int {
		points.filter { $0.success }.count
	}

	var failedPoints: Int {
		points.filter { !$0.success }.count
	}

	var successRate: Double {
		guard totalPoints > 0 else { return 0 }
		return Double(successfulPoints) / Double(totalPoints)
	}

	var averageSNR: Float {
		let successfulSNRs = points.filter { $0.success }.map { $0.snr }
		guard !successfulSNRs.isEmpty else { return 0 }
		return successfulSNRs.reduce(0, +) / Float(successfulSNRs.count)
	}

	var minSNR: Float {
		points.filter { $0.success }.map { $0.snr }.min() ?? 0
	}

	var maxSNR: Float {
		points.filter { $0.success }.map { $0.snr }.max() ?? 0
	}

	var averageResponseTime: TimeInterval {
		let times = points.compactMap { $0.responseTime }
		guard !times.isEmpty else { return 0 }
		return times.reduce(0, +) / Double(times.count)
	}

	var duration: TimeInterval {
		guard let first = points.first?.timestamp,
			  let last = points.last?.timestamp else {
			return 0
		}
		return last.timeIntervalSince(first)
	}

	/// Total distance covered in meters
	var totalDistance: Double {
		guard points.count > 1 else { return 0 }
		var distance: Double = 0
		for i in 0..<(points.count - 1) {
			let loc1 = CLLocation(latitude: points[i].latitude, longitude: points[i].longitude)
			let loc2 = CLLocation(latitude: points[i + 1].latitude, longitude: points[i + 1].longitude)
			distance += loc1.distance(from: loc2)
		}
		return distance
	}
}

// MARK: - Session Storage

/// Manager for persisting mapping sessions to JSON files
class SignalMappingStorage {
	static let shared = SignalMappingStorage()

	private let fileManager = FileManager.default
	private let sessionDirectory: URL

	private init() {
		let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
		sessionDirectory = documentsPath.appendingPathComponent("SignalMappingSessions", isDirectory: true)

		// Create directory if it doesn't exist
		try? fileManager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
	}

	/// Save a session to JSON file
	func saveSession(_ session: MappingSession) throws {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

		let data = try encoder.encode(session)
		let filename = "\(session.id.uuidString).json"
		let fileURL = sessionDirectory.appendingPathComponent(filename)

		try data.write(to: fileURL)
	}

	/// Load a session from JSON file
	func loadSession(id: UUID) throws -> MappingSession {
		let filename = "\(id.uuidString).json"
		let fileURL = sessionDirectory.appendingPathComponent(filename)

		let data = try Data(contentsOf: fileURL)
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601

		return try decoder.decode(MappingSession.self, from: data)
	}

	/// Load all sessions
	func loadAllSessions() throws -> [MappingSession] {
		let fileURLs = try fileManager.contentsOfDirectory(at: sessionDirectory, includingPropertiesForKeys: nil)
		let jsonFiles = fileURLs.filter { $0.pathExtension == "json" }

		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601

		return try jsonFiles.compactMap { url in
			let data = try Data(contentsOf: url)
			return try? decoder.decode(MappingSession.self, from: data)
		}.sorted { $0.lastUpdated > $1.lastUpdated }
	}

	/// Delete a session
	func deleteSession(id: UUID) throws {
		let filename = "\(id.uuidString).json"
		let fileURL = sessionDirectory.appendingPathComponent(filename)
		try fileManager.removeItem(at: fileURL)
	}

	/// Export session to a shareable URL
	func exportSession(_ session: MappingSession) throws -> URL {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

		let data = try encoder.encode(session)
		let filename = "\(session.name.replacingOccurrences(of: " ", with: "_"))_\(session.id.uuidString).json"
		let tempURL = fileManager.temporaryDirectory.appendingPathComponent(filename)

		try data.write(to: tempURL)
		return tempURL
	}

	/// Import session from URL
	func importSession(from url: URL) throws -> MappingSession {
		let data = try Data(contentsOf: url)
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601

		let session = try decoder.decode(MappingSession.self, from: data)
		try saveSession(session)
		return session
	}
}
