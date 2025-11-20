//
//  SignalMapping.swift
//  Meshtastic
//
//  Signal mapping and RF coverage testing view
//

import SwiftUI
import CoreData
import CoreLocation
import MapKit
import OSLog

struct SignalMapping: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager

	@ObservedObject var router: Router

	// Signal Mapping Manager
	@StateObject private var mappingManager: SignalMappingManager

	// Map Configuration
	@Namespace var mapScope
	@State private var mapStyle: MapStyle = MapStyle.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false)
	@State private var position = MapCameraPosition.userLocation(followsHeading: false, fallback: .automatic)

	// UI State
	@State private var showingSessionList = false
	@State private var showingNewSessionSheet = false
	@State private var selectedNodeNum: Int64 = 0
	@State private var sessionName: String = ""
	@State private var probeInterval: TimeInterval = 10.0

	// Sessions
	@State private var sessions: [MappingSession] = []

	init(router: Router, accessoryManager: AccessoryManager) {
		self.router = router
		self._mappingManager = StateObject(wrappedValue: SignalMappingManager(accessoryManager: accessoryManager))
	}

	var body: some View {
		NavigationStack {
			ZStack {
				// Map View
				MapReader { reader in
					Map(
						position: $position,
						scope: mapScope
					) {
						// User location
						UserAnnotation()

						// Signal mapping points
						if let session = mappingManager.currentSession {
							ForEach(session.points) { point in
								Annotation("", coordinate: point.coordinate) {
									SignalPointAnnotation(point: point)
								}
							}
						}
					}
					.mapScope(mapScope)
					.mapStyle(mapStyle)
					.mapControls {
						MapScaleView(scope: mapScope)
							.mapControlVisibility(.automatic)
						MapCompass(scope: mapScope)
							.mapControlVisibility(.automatic)
					}
					.controlSize(.regular)
				}

				// Control Panel (Top)
				VStack {
					SignalMappingControlPanel(
						mappingManager: mappingManager,
						showingNewSessionSheet: $showingNewSessionSheet,
						showingSessionList: $showingSessionList
					)
					.padding(.horizontal)
					.padding(.top, 50)

					Spacer()
				}
			}
			.navigationTitle("Signal Mapping")
			.navigationBarTitleDisplayMode(.inline)
			.sheet(isPresented: $showingNewSessionSheet) {
				NewSessionSheet(
					mappingManager: mappingManager,
					sessionName: $sessionName,
					selectedNodeNum: $selectedNodeNum,
					probeInterval: $probeInterval,
					isPresented: $showingNewSessionSheet
				)
			}
			.sheet(isPresented: $showingSessionList) {
				SessionListSheet(
					mappingManager: mappingManager,
					sessions: $sessions,
					isPresented: $showingSessionList
				)
			}
			.onAppear {
				sessions = mappingManager.loadAllSessions()
			}
		}
	}
}

// MARK: - Control Panel

struct SignalMappingControlPanel: View {
	@ObservedObject var mappingManager: SignalMappingManager
	@Binding var showingNewSessionSheet: Bool
	@Binding var showingSessionList: Bool

	var body: some View {
		VStack(spacing: 12) {
			// Current Session Info & Controls
			HStack {
				if mappingManager.isMapping {
					// Active session info
					VStack(alignment: .leading, spacing: 4) {
						Text(mappingManager.currentSession?.name ?? "Unknown")
							.font(.headline)
						Text("\(mappingManager.currentSession?.totalPoints ?? 0) points")
							.font(.caption)
							.foregroundStyle(.secondary)
					}

					Spacer()

					// Stop button
					Button(action: {
						mappingManager.stopSession()
					}) {
						Label("Stop", systemImage: "stop.circle.fill")
							.foregroundStyle(.white)
							.padding(.horizontal, 16)
							.padding(.vertical, 8)
							.background(Color.red)
							.clipShape(RoundedRectangle(cornerRadius: 8))
					}
				} else {
					// Start button
					Button(action: {
						showingNewSessionSheet = true
					}) {
						Label("Start Mapping", systemImage: "play.circle.fill")
							.foregroundStyle(.white)
							.padding(.horizontal, 16)
							.padding(.vertical, 8)
							.background(Color.green)
							.clipShape(RoundedRectangle(cornerRadius: 8))
					}

					Spacer()

					// Sessions button
					Button(action: {
						showingSessionList = true
					}) {
						Label("Sessions", systemImage: "list.bullet")
							.foregroundStyle(.white)
							.padding(.horizontal, 16)
							.padding(.vertical, 8)
							.background(Color.blue)
							.clipShape(RoundedRectangle(cornerRadius: 8))
					}
				}
			}

			// Live Stats (when mapping)
			if mappingManager.isMapping {
				HStack(spacing: 16) {
					StatView(title: "SNR", value: String(format: "%.1f dB", mappingManager.currentSNR), color: snrColor(mappingManager.currentSNR))
					StatView(title: "RSSI", value: "\(mappingManager.currentRSSI) dBm", color: .orange)
					if let session = mappingManager.currentSession {
						StatView(title: "Success", value: String(format: "%.0f%%", session.successRate * 100), color: .green)
					}
				}
			}
		}
		.padding()
		.background(.ultraThinMaterial)
		.clipShape(RoundedRectangle(cornerRadius: 12))
	}

	private func snrColor(_ snr: Float) -> Color {
		if snr >= 10 { return .green }
		if snr >= 5 { return .mint }
		if snr >= 0 { return .yellow }
		if snr >= -5 { return .orange }
		return .red
	}
}

// MARK: - Stat View

struct StatView: View {
	let title: String
	let value: String
	let color: Color

	var body: some View {
		VStack(spacing: 4) {
			Text(value)
				.font(.system(.body, design: .rounded))
				.fontWeight(.semibold)
				.foregroundStyle(color)
			Text(title)
				.font(.caption2)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity)
	}
}

// MARK: - Signal Point Annotation

struct SignalPointAnnotation: View {
	let point: MappingPoint

	var body: some View {
		Circle()
			.fill(pointColor)
			.frame(width: 8, height: 8)
			.overlay {
				Circle()
					.stroke(.white, lineWidth: 1)
			}
	}

	private var pointColor: Color {
		if !point.success {
			return .red
		}

		let snr = point.snr
		if snr >= 10 { return .green }
		if snr >= 5 { return .mint }
		if snr >= 0 { return .yellow }
		if snr >= -5 { return .orange }
		return .red
	}
}

// MARK: - New Session Sheet

struct NewSessionSheet: View {
	@ObservedObject var mappingManager: SignalMappingManager
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Binding var sessionName: String
	@Binding var selectedNodeNum: Int64
	@Binding var probeInterval: TimeInterval
	@Binding var isPresented: Bool

	@Environment(\.managedObjectContext) private var context
	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(keyPath: \NodeInfoEntity.lastHeard, ascending: false)],
		animation: .default)
	private var nodes: FetchedResults<NodeInfoEntity>

	private var availableNodes: [NodeInfoEntity] {
		nodes.filter { $0.num != accessoryManager.activeDeviceNum && $0.num > 0 }
	}

	var body: some View {
		NavigationStack {
			Form {
				Section("Session Details") {
					TextField("Session Name", text: $sessionName)
				}

				Section("Target Node") {
					if availableNodes.isEmpty {
						Text("No nodes available")
							.foregroundStyle(.secondary)
					} else {
						Picker("Node to Ping", selection: $selectedNodeNum) {
							ForEach(availableNodes, id: \.num) { node in
								Text(node.user?.longName ?? "Unknown")
									.tag(Int64(node.num))
							}
						}
					}
				}

				Section("Probe Settings") {
					Picker("Probe Interval", selection: $probeInterval) {
						Text("5 seconds").tag(5.0)
						Text("10 seconds").tag(10.0)
						Text("15 seconds").tag(15.0)
						Text("30 seconds").tag(30.0)
						Text("60 seconds").tag(60.0)
					}
				}

				Section {
					Text("Signal mapping will send probe messages to the selected node at the specified interval. GPS location with signal quality (SNR/RSSI) will be recorded for each response.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}
			.navigationTitle("New Mapping Session")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") {
						isPresented = false
					}
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Start") {
						Logger.services.info("[SignalMapping UI] Start button pressed - sessionName=\(sessionName, privacy: .public), isEmpty=\(sessionName.isEmpty, privacy: .public)")
						startSession()
					}
					.disabled(sessionName.isEmpty || selectedNodeNum == 0 || availableNodes.isEmpty)
				}
			}
			.onAppear {
				// Set defaults
				Logger.services.info("[SignalMapping UI] NewSessionSheet onAppear - setting default session name")
				sessionName = "Session \(Date().formatted(date: .abbreviated, time: .shortened))"
				Logger.services.info("[SignalMapping UI] NewSessionSheet onAppear - sessionName set to: \(sessionName, privacy: .public)")
				// Set first available node as default
				if let firstNode = availableNodes.first {
					selectedNodeNum = Int64(firstNode.num)
					Logger.services.info("[SignalMapping UI] Selected first node: \(firstNode.user?.longName ?? "Unknown") (\(selectedNodeNum.toHex(), privacy: .public))")
				}
			}
		}
	}

	private func startSession() {
		// Find the selected node to get its name
		let selectedNode = availableNodes.first { Int64($0.num) == selectedNodeNum }
		let nodeName = selectedNode?.user?.longName ?? "Unknown Node"

		Logger.services.info("[SignalMapping UI] startSession() called in UI - name=\(sessionName, privacy: .public), targetNode=\(selectedNodeNum.toHex(), privacy: .public), targetNodeName=\(nodeName, privacy: .public)")
		mappingManager.startSession(
			name: sessionName,
			targetNodeNum: selectedNodeNum,
			targetNodeName: nodeName,
			probeInterval: probeInterval
		)
		Logger.services.info("[SignalMapping UI] Called mappingManager.startSession()")
		isPresented = false
	}
}

// MARK: - Session List Sheet

struct SessionListSheet: View {
	@ObservedObject var mappingManager: SignalMappingManager
	@Binding var sessions: [MappingSession]
	@Binding var isPresented: Bool

	var body: some View {
		NavigationStack {
			List {
				ForEach(sessions) { session in
					SessionRow(session: session)
						.swipeActions(edge: .trailing, allowsFullSwipe: false) {
							Button(role: .destructive) {
								deleteSession(session)
							} label: {
								Label("Delete", systemImage: "trash")
							}

							Button {
								exportSession(session)
							} label: {
								Label("Export", systemImage: "square.and.arrow.up")
							}
							.tint(.blue)
						}
						.contentShape(Rectangle())
						.onTapGesture {
							if !session.isActive {
								mappingManager.resumeSession(session)
								isPresented = false
							}
						}
				}
			}
			.navigationTitle("Mapping Sessions")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Done") {
						isPresented = false
					}
				}
				ToolbarItem(placement: .primaryAction) {
					Button {
						// Import session
					} label: {
						Label("Import", systemImage: "square.and.arrow.down")
					}
				}
			}
			.onAppear {
				sessions = mappingManager.loadAllSessions()
			}
		}
	}

	private func deleteSession(_ session: MappingSession) {
		mappingManager.deleteSession(session)
		sessions = mappingManager.loadAllSessions()
	}

	private func exportSession(_ session: MappingSession) {
		if let url = mappingManager.exportSession(session) {
			// Share the exported file
			let activityController = UIActivityViewController(
				activityItems: [url],
				applicationActivities: nil
			)

			if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
			   let window = windowScene.windows.first,
			   let rootViewController = window.rootViewController {
				rootViewController.present(activityController, animated: true)
			}
		}
	}
}

// MARK: - Session Row

struct SessionRow: View {
	let session: MappingSession

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack {
				Text(session.name)
					.font(.headline)
				Spacer()
				if session.isActive {
					Text("Active")
						.font(.caption)
						.padding(.horizontal, 8)
						.padding(.vertical, 2)
						.background(Color.green.opacity(0.2))
						.foregroundStyle(.green)
						.clipShape(Capsule())
				}
			}

			HStack {
				Text("\(session.totalPoints) points")
					.font(.caption)
				Text("•")
					.foregroundStyle(.secondary)
				Text(String(format: "%.0f%% success", session.successRate * 100))
					.font(.caption)
			}
			.foregroundStyle(.secondary)

			HStack {
				if session.totalPoints > 0 {
					Text("SNR: \(String(format: "%.1f", session.averageSNR)) dB avg")
						.font(.caption2)
					Text("•")
						.foregroundStyle(.secondary)
				}
				Text(session.lastUpdated.formatted(date: .abbreviated, time: .shortened))
					.font(.caption2)
			}
			.foregroundStyle(.secondary)
		}
		.padding(.vertical, 4)
	}
}
