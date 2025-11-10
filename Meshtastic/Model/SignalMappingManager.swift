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
	private var pendingProbes: [Int64: Date] = [:] // Track sent probes by messageId

	// Global accessor for ACK handling
	static weak var shared: SignalMappingManager?

	init(accessoryManager: AccessoryManager) {
		self.accessoryManager = accessoryManager
		SignalMappingManager.shared = self
	}

	// MARK: - Session Control

	/// Start a new mapping session
	func startSession(name: String, targetNodeNum: Int64, targetNodeName: String, probeInterval: TimeInterval = 10.0) {
		Logger.services.info("[SignalMapping] startSession() called - name=\(name, privacy: .public), targetNode=\(targetNodeNum.toHex(), privacy: .public), targetNodeName=\(targetNodeName, privacy: .public), interval=\(probeInterval, privacy: .public)")

		guard !isMapping else {
			Logger.services.error("[SignalMapping] startSession() rejected - already mapping")
			return
		}

		let session = MappingSession(
			name: name,
			targetNodeNum: targetNodeNum,
			targetNodeName: targetNodeName,
			probeInterval: probeInterval,
			isActive: true
		)

		currentSession = session
		isMapping = true

		Logger.services.info("[SignalMapping] Session created - calling startProbing()")
		startProbing()
		Logger.services.info("[SignalMapping] Started session: \(name, privacy: .public) targeting node: \(targetNodeName, privacy: .public)")
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
		Logger.services.info("[SignalMapping] startProbing() called")

		guard let session = currentSession else {
			Logger.services.error("[SignalMapping] startProbing() failed - no session")
			return
		}

		Logger.services.info("[SignalMapping] Creating timer with interval=\(session.probeInterval, privacy: .public)")
		probeTimer = Timer.scheduledTimer(withTimeInterval: session.probeInterval, repeats: true) { [weak self] _ in
			Logger.services.info("[SignalMapping] Timer fired - calling sendProbe()")
			Task { @MainActor in
				await self?.sendProbe()
			}
		}

		// Send first probe immediately
		Logger.services.info("[SignalMapping] Sending first probe immediately")
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
		Logger.services.info("[SignalMapping] sendProbe() called - isMapping=\(self.isMapping, privacy: .public), hasSession=\(self.currentSession != nil, privacy: .public), hasLocation=\(LocationsHandler.shared.locationsArray.last != nil, privacy: .public)")

		guard let session = currentSession,
			  isMapping,
			  let location = LocationsHandler.shared.locationsArray.last else {
			Logger.services.error("[SignalMapping] sendProbe() guard failed - cannot send probe")
			return
		}

		let sendTime = Date()

		// Send minimal probe message (1 character) to target node
		do {
			let messageId = try await accessoryManager.sendMessage(
				message: ".", // Minimal payload
				toUserNum: session.targetNodeNum,
				channel: 0, // Direct message (channel doesn't matter)
				isEmoji: false,
				replyID: 0
			)

			// Store probe messageId and send time
			pendingProbes[messageId] = sendTime

			Logger.services.info("[SignalMapping] Probe sent to node \(session.targetNodeNum.toHex(), privacy: .public) with messageId: \(messageId, privacy: .public) (hex: \(messageId.toHex(), privacy: .public))")
			Logger.services.info("[SignalMapping] All pending probes: \(self.pendingProbes.keys.map { "\($0) (\($0.toHex()))" }.joined(separator: ", "), privacy: .public)")

			// Wait for ACK (timeout after 30 seconds)
			Task {
				try? await Task.sleep(nanoseconds: 30_000_000_000)
				await handleProbeTimeout(messageId: messageId, location: location)
			}

		} catch {
			Logger.services.error("[SignalMapping] Failed to send probe: \(error.localizedDescription)")

			// Create failed point
			await addFailedPoint(location: location)
		}
	}

	/// Handle probe ACK received
	func handleProbeACK(messageId: Int64, responderNodeNum: Int64, snr: Float, rssi: Int32) {
		Logger.services.info("[SignalMapping] handleProbeACK called: msgID=\(messageId, privacy: .public) (\(messageId.toHex(), privacy: .public)) from=\(responderNodeNum.toHex(), privacy: .public) SNR=\(snr, privacy: .public) RSSI=\(rssi, privacy: .public)")
		Logger.services.info("[SignalMapping] Pending probes: \(self.pendingProbes.keys.map { "\($0) (\($0.toHex()))" }.joined(separator: ", "), privacy: .public)")
		Logger.services.info("[SignalMapping] Is mapping: \(self.isMapping, privacy: .public), Has session: \(self.currentSession != nil, privacy: .public)")

		guard let sendTime = pendingProbes.removeValue(forKey: messageId),
			  let location = LocationsHandler.shared.locationsArray.last,
			  var session = currentSession else {
			Logger.services.error("[SignalMapping] ACK ignored - messageId=\(messageId, privacy: .public) (\(messageId.toHex(), privacy: .public)) not in pending probes: [\(self.pendingProbes.keys.map { "\($0) (\($0.toHex()))" }.joined(separator: ", "), privacy: .public)]")
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
			channel: 0, // Direct message
			responderNodeNum: responderNodeNum,
			responseTime: responseTime,
			success: true
		)

		session.points.append(point)
		session.lastUpdated = Date()
		currentSession = session
		lastPoint = point
		currentSNR = snr
		currentRSSI = rssi

		Logger.services.info("[SignalMapping] Point recorded from node \(responderNodeNum.toHex()): SNR=\(snr) RSSI=\(rssi)")
	}

	private func handleProbeTimeout(messageId: Int64, location: CLLocation) async {
		guard pendingProbes[messageId] != nil else {
			// Already handled (ACK received)
			return
		}

		pendingProbes.removeValue(forKey: messageId)
		await addFailedPoint(location: location)
	}

	private func addFailedPoint(location: CLLocation) async {
		guard var session = currentSession else { return }

		let point = MappingPoint(
			timestamp: Date(),
			latitude: location.coordinate.latitude,
			longitude: location.coordinate.longitude,
			altitude: location.altitude,
			horizontalAccuracy: location.horizontalAccuracy,
			snr: -999, // Indicate no signal
			rssi: -999,
			channel: 0, // Direct message
			responderNodeNum: 0, // 0 indicates no responder
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
