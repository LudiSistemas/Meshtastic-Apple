//
//  SignalMappingManager.swift
//  Meshtastic
//
//  Manager for RF signal mapping and coverage testing
//

import Foundation
import CoreLocation
import OSLog
import Combine

@MainActor
class SignalMappingManager: ObservableObject {
	@Published var currentSession: MappingSession?
	@Published var isMapping: Bool = false
	@Published var lastPoint: MappingPoint?
	@Published var currentSNR: Float = 0
	@Published var currentRSSI: Int32 = 0

	private var accessoryManager: AccessoryManager
	private var probeTimer: Timer?
	private var storage = SignalMappingStorage.shared
	private var pendingProbes: [UUID: Date] = [:] // Track sent probes

	init(accessoryManager: AccessoryManager) {
		self.accessoryManager = accessoryManager
	}

	// MARK: - Session Control

	/// Start a new mapping session
	func startSession(name: String, channel: UInt32, targetNodeNum: Int64, probeInterval: TimeInterval = 10.0) {
		guard !isMapping else { return }

		let session = MappingSession(
			name: name,
			channel: channel,
			targetNodeNum: targetNodeNum,
			probeInterval: probeInterval,
			isActive: true
		)

		currentSession = session
		isMapping = true

		startProbing()
		Logger.services.info("[SignalMapping] Started session: \(name)")
	}

	/// Stop current mapping session
	func stopSession() {
		guard isMapping, var session = currentSession else { return }

		isMapping = false
		session.isActive = false
		session.lastUpdated = Date()
		currentSession = session

		stopProbing()

		// Save session
		Task {
			do {
				try storage.saveSession(session)
				Logger.services.info("[SignalMapping] Session saved: \(session.id)")
			} catch {
				Logger.services.error("[SignalMapping] Failed to save session: \(error.localizedDescription)")
			}
		}
	}

	/// Resume existing session
	func resumeSession(_ session: MappingSession) {
		currentSession = session
		isMapping = true
		startProbing()
	}

	// MARK: - Probing

	private func startProbing() {
		guard let session = currentSession else { return }

		probeTimer = Timer.scheduledTimer(withTimeInterval: session.probeInterval, repeats: true) { [weak self] _ in
			Task { @MainActor in
				await self?.sendProbe()
			}
		}

		// Send first probe immediately
		Task {
			await sendProbe()
		}
	}

	private func stopProbing() {
		probeTimer?.invalidate()
		probeTimer = nil
		pendingProbes.removeAll()
	}

	/// Send a probe message to target node
	private func sendProbe() async {
		guard let session = currentSession,
			  isMapping,
			  let location = LocationsHandler.shared.locationsArray.last else {
			return
		}

		let probeId = UUID()
		let sendTime = Date()

		// Store probe ID and send time
		pendingProbes[probeId] = sendTime

		// Send minimal probe message (1 character)
		do {
			try await accessoryManager.sendMessage(
				message: ".", // Minimal payload
				toUserNum: session.targetNodeNum,
				channel: Int32(session.channel),
				isEmoji: false,
				replyID: 0
			)

			Logger.services.info("[SignalMapping] Probe sent: \(probeId)")

			// Wait for ACK (timeout after 30 seconds)
			Task {
				try? await Task.sleep(nanoseconds: 30_000_000_000)
				handleProbeTimeout(probeId: probeId, location: location)
			}

		} catch {
			Logger.services.error("[SignalMapping] Failed to send probe: \(error.localizedDescription)")

			// Create failed point
			addFailedPoint(probeId: probeId, location: location)
		}
	}

	/// Handle probe ACK received
	func handleProbeACK(probeId: UUID, snr: Float, rssi: Int32) {
		guard let sendTime = pendingProbes.removeValue(forKey: probeId),
			  let location = LocationsHandler.shared.locationsArray.last,
			  var session = currentSession else {
			return
		}

		let responseTime = Date().timeIntervalSince(sendTime)

		let point = MappingPoint(
			timestamp: Date(),
			latitude: location.coordinate.latitude,
			longitude: location.coordinate.longitude,
			altitude: location.altitude,
			horizontalAccuracy: location.horizontalAccuracy,
			snr: snr,
			rssi: rssi,
			channel: session.channel,
			targetNodeNum: session.targetNodeNum,
			responseTime: responseTime,
			success: true
		)

		session.points.append(point)
		session.lastUpdated = Date()
		currentSession = session
		lastPoint = point
		currentSNR = snr
		currentRSSI = rssi

		Logger.services.info("[SignalMapping] Point recorded: SNR=\(snr) RSSI=\(rssi)")
	}

	private func handleProbeTimeout(probeId: UUID, location: CLLocation) {
		guard pendingProbes[probeId] != nil else {
			// Already handled (ACK received)
			return
		}

		pendingProbes.removeValue(forKey: probeId)
		addFailedPoint(probeId: probeId, location: location)
	}

	private func addFailedPoint(probeId: UUID, location: CLLocation) {
		guard var session = currentSession else { return }

		let point = MappingPoint(
			timestamp: Date(),
			latitude: location.coordinate.latitude,
			longitude: location.coordinate.longitude,
			altitude: location.altitude,
			horizontalAccuracy: location.horizontalAccuracy,
			snr: -999, // Indicate no signal
			rssi: -999,
			channel: session.channel,
			targetNodeNum: session.targetNodeNum,
			responseTime: nil,
			success: false
		)

		session.points.append(point)
		session.lastUpdated = Date()
		currentSession = session
		lastPoint = point

		Logger.services.info("[SignalMapping] Failed point recorded (no ACK)")
	}

	// MARK: - Session Management

	func loadAllSessions() -> [MappingSession] {
		do {
			return try storage.loadAllSessions()
		} catch {
			Logger.services.error("[SignalMapping] Failed to load sessions: \(error.localizedDescription)")
			return []
		}
	}

	func deleteSession(_ session: MappingSession) {
		do {
			try storage.deleteSession(id: session.id)
			if currentSession?.id == session.id {
				currentSession = nil
			}
		} catch {
			Logger.services.error("[SignalMapping] Failed to delete session: \(error.localizedDescription)")
		}
	}

	func exportSession(_ session: MappingSession) -> URL? {
		do {
			return try storage.exportSession(session)
		} catch {
			Logger.services.error("[SignalMapping] Failed to export session: \(error.localizedDescription)")
			return nil
		}
	}

	func importSession(from url: URL) -> MappingSession? {
		do {
			return try storage.importSession(from: url)
		} catch {
			Logger.services.error("[SignalMapping] Failed to import session: \(error.localizedDescription)")
			return nil
		}
	}
}
