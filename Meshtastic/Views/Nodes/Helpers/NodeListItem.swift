//
//  NodeListItem.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 9/8/23.
//

import SwiftUI
import CoreLocation
import MapKit
import Foundation

struct NodeListItem: View {

	// Animation states
	@State private var pulseAnimation = false

	private var accessibilityDescription: String {
		var desc = ""
		if let shortName = node.user?.shortName {
			desc = shortName.formatNodeNameForVoiceOver()
		} else if let longName = node.user?.longName {
			desc = longName
		} else {
			desc = "Unknown".localized + " " + "Node".localized
		}
		if isDirectlyConnected {
			desc += ", currently connected"
		}
		if node.favorite {
			desc += ", favorite"
		}
		if node.lastHeard != nil {
			let formatter = RelativeDateTimeFormatter()
			formatter.unitsStyle = .full
			let relative = formatter.localizedString(for: node.lastHeard!, relativeTo: Date())
			desc += ", last heard " + relative
		}
		if node.isOnline {
			desc += ", online"
		} else {
			desc += ", offline"
		}
		let role = DeviceRoles(rawValue: Int(node.user?.role ?? 0))
		if let roleName = role?.name {
			desc += ", role: \(roleName)"
		}
		if node.hopsAway > 0 {
			desc += ", \(node.hopsAway) hops away"
		}
		if let battery = node.latestDeviceMetrics?.batteryLevel {
			if battery > 100 {
				desc += ", " + "Plugged in".localized
			} else if battery == 100 {
				desc += ", " + "Charging".localized
			} else {
				desc += ", battery \(battery)%"
			}
		}
		if !isDirectlyConnected, let (lastPosition, myCoord) = locationData {
			let nodeCoord = CLLocation(latitude: lastPosition.nodeCoordinate!.latitude, longitude: lastPosition.nodeCoordinate!.longitude)
			let metersAway = nodeCoord.distance(from: myCoord)
			let distanceFormatter = LengthFormatter()
			distanceFormatter.unitStyle = .medium
			let formattedDistance = distanceFormatter.string(fromMeters: metersAway)
			desc += ", " + String(format: "%@: %@", "Distance".localized, formattedDistance)
			let trueBearing = getBearingBetweenTwoPoints(point1: myCoord, point2: nodeCoord)
			let heading = Measurement(value: trueBearing, unit: UnitAngle.degrees)
			let formattedHeading = heading.formatted(.measurement(width: .narrow, numberFormatStyle: .number.precision(.fractionLength(0))))
			desc += ", " + "Heading".localized + " " + formattedHeading
		}
		if node.snr != 0 && !node.viaMqtt {
			let signalStrength: BLESignalStrength
			if node.snr < -10 {
				signalStrength = .weak
			} else if node.snr < 5 {
				signalStrength = .normal
			} else {
				signalStrength = .strong
			}
			let signalString: String
			switch signalStrength {
			case .weak:
				signalString = "Signal strength weak".localized
			case .normal:
				signalString = "Signal strength normal".localized
			case .strong:
				signalString = "Signal strength strong".localized
			}
			desc += ", " + signalString
		}
		return desc
	}
	
	@ObservedObject var node: NodeInfoEntity
	var isDirectlyConnected: Bool
	var connectedNode: Int64
	var modemPreset: ModemPresets = ModemPresets(rawValue: UserDefaults.modemPreset) ?? ModemPresets.longFast
	
	var userKeyStatus: (String, Color) {
		var image = "lock.open.fill"
		var color = Color.yellow
		if node.user?.pkiEncrypted ?? false {
			if !(node.user?.keyMatch ?? false) {
				image = "key.slash"
				color = .red
			} else {
				image = "lock.fill"
				color = .green
			}
		}
		return (image, color)
	}
	
	var locationData: (PositionEntity, CLLocation)? {
		guard let lastPostion = node.positions?.lastObject as? PositionEntity else {
			return nil
		}
		guard let currentLocation = LocationsHandler.shared.locationsArray.last else {
			return nil
		}

		let myCoord = CLLocation(latitude: currentLocation.coordinate.latitude, longitude: currentLocation.coordinate.longitude)

		if lastPostion.nodeCoordinate != nil && myCoord.coordinate.longitude != LocationsHandler.DefaultLocation.longitude && myCoord.coordinate.latitude != LocationsHandler.DefaultLocation.latitude {
			return (lastPostion, myCoord)
		}
		return nil
	}

	// Card gradient based on node status
	private var cardGradient: LinearGradient {
		if isDirectlyConnected {
			return LinearGradient(
				colors: [Color.green.opacity(0.15), Color.green.opacity(0.05)],
				startPoint: .topLeading,
				endPoint: .bottomTrailing
			)
		} else if node.isOnline {
			return LinearGradient(
				colors: [Color.blue.opacity(0.10), Color.blue.opacity(0.03)],
				startPoint: .topLeading,
				endPoint: .bottomTrailing
			)
		} else {
			return LinearGradient(
				colors: [Color.gray.opacity(0.08), Color.gray.opacity(0.02)],
				startPoint: .topLeading,
				endPoint: .bottomTrailing
			)
		}
	}
	
	var body: some View {
		LazyVStack(alignment: .leading) {
			HStack {
				VStack(alignment: .center) {
					CircleText(text: node.user?.shortName ?? "?", color: Color(UIColor(hex: UInt32(node.num))), circleSize: 70)
						.padding(.trailing, 5)
					if node.latestDeviceMetrics != nil {
						BatteryCompact(batteryLevel: node.latestDeviceMetrics?.batteryLevel ?? 0, font: .caption, iconFont: .callout, color: .accentColor)
							.padding(.trailing, 5)
					}
				}
				VStack(alignment: .leading) {
					HStack {
						let (image, color) = userKeyStatus
						IconAndText(systemName: image,
									imageColor: color,
									text: node.user?.longName?.addingVariationSelectors ?? "Unknown".localized,
									textColor: .primary)
						if node.favorite {
							Spacer()
							Image(systemName: "star.fill")
								.symbolRenderingMode(.multicolor)
						}
					}
					if isDirectlyConnected {
						IconAndText(systemName: "antenna.radiowaves.left.and.right.circle.fill",
									imageColor: .green,
									text: "Connected".localized)
					}
					if node.lastHeard?.timeIntervalSince1970 ?? 0 > 0 && node.lastHeard! < Calendar.current.date(byAdding: .year, value: 1, to: Date())! {
						IconAndText(systemName: node.isOnline ? "checkmark.circle.fill" : "moon.circle.fill",
									imageColor: node.isOnline ? .green : .orange,
									text: node.lastHeard?.formatted() ?? "Unknown Age".localized)
					}
					let role = DeviceRoles(rawValue: Int(node.user?.role ?? 0))
					IconAndText(systemName: role?.systemName ?? "figure",
								text: "Role: \(role?.name ?? "Unknown".localized)")
					if node.user?.unmessagable ?? false {
						IconAndText(systemName: "iphone.slash",
									renderingMode: .multicolor,
									text: "Unmonitored")
					}
					if node.isStoreForwardRouter {
						IconAndText(systemName: "envelope.arrow.triangle.branch",
									renderingMode: .multicolor,
									text: "Store & Forward".localized)
					}
					
					if node.positions?.count ?? 0 > 0 && connectedNode != node.num {
						HStack {
							if let (lastPostion, myCoord) = locationData {
								let nodeCoord = CLLocation(latitude: lastPostion.nodeCoordinate!.latitude, longitude: lastPostion.nodeCoordinate!.longitude)
								let metersAway = nodeCoord.distance(from: myCoord)
								Image(systemName: "lines.measurement.horizontal")
									.font(.callout)
									.symbolRenderingMode(.multicolor)
									.frame(width: 30)
								DistanceText(meters: metersAway)
									.font(UIDevice.current.userInterfaceIdiom == .phone ? .callout : .caption)
									.foregroundColor(.gray)
								let trueBearing = getBearingBetweenTwoPoints(point1: myCoord, point2: nodeCoord)
								let headingDegrees = Measurement(value: trueBearing, unit: UnitAngle.degrees)
								Image(systemName: "location.north")
									.font(.callout)
									.symbolRenderingMode(.multicolor)
									.clipShape(Circle())
									.rotationEffect(Angle(degrees: headingDegrees.value))
								let heading = Measurement(value: trueBearing, unit: UnitAngle.degrees)
								Text("\(heading.formatted(.measurement(width: .narrow, numberFormatStyle: .number.precision(.fractionLength(0)))))")
									.font(UIDevice.current.userInterfaceIdiom == .phone ? .callout : .caption)
									.foregroundColor(.gray)
							}
						}
					}
					HStack {
						if node.channel > 0 {
							IconAndText(systemName: "\(node.channel).circle.fill", text: "Channel")
						}
						
						if node.viaMqtt && connectedNode != node.num {
							IconAndText(systemName: "dot.radiowaves.up.forward",
										renderingMode: .multicolor,
										text: "MQTT")
						}
					}
					if node.hasPositions || node.hasEnvironmentMetrics || node.hasDetectionSensorMetrics || node.hasTraceRoutes {
						HStack {
							IconAndText(systemName: "scroll", text: "Logs:")
							if node.hasDeviceMetrics {
								DefaultIcon(systemName: "flipphone")
							}
							if node.hasPositions {
								DefaultIcon(systemName: "mappin.and.ellipse")
							}
							if node.hasEnvironmentMetrics {
								DefaultIcon(systemName: "cloud.sun.rain")
							}
							if node.hasDetectionSensorMetrics {
								DefaultIcon(systemName: "sensor")
							}
							if node.hasTraceRoutes {
								DefaultIcon(systemName: "signpost.right.and.left")
							}
						}
					}
					if node.hopsAway > 0 {
						HStack {
							IconAndText(systemName: "hare", text: "Hops Away:")
							Image(systemName: "\(node.hopsAway).square")
								.font(.title2)
						}
					} else {
						if node.snr != 0 && !node.viaMqtt {
							LoRaSignalStrengthMeter(snr: node.snr, rssi: node.rssi, preset: modemPreset, compact: true)
								.padding(.top, node.hasPositions || node.hasEnvironmentMetrics || node.hasDetectionSensorMetrics || node.hasTraceRoutes ? 0 : 15)
						}
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}

			// Activity Timeline
			if node.positions?.count ?? 0 > 0 {
				ActivityTimeline(node: node)
			}

			// Mini Map Thumbnail
			if locationData != nil {
				MiniMapThumbnail(node: node, locationData: locationData)
			}

			// Quick Stats Panel
			QuickStatsPanel(node: node, locationData: locationData, modemPreset: modemPreset)
		}
		.padding(12)
		.background(cardGradient)
		.cornerRadius(12)
		.shadow(
			color: Color.black.opacity(isDirectlyConnected && pulseAnimation ? 0.15 : 0.08),
			radius: isDirectlyConnected && pulseAnimation ? 8 : 4,
			x: 0,
			y: 2
		)
		.padding(.horizontal, 8)
		.padding(.vertical, 4)
		.animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseAnimation)
		.onAppear {
			if isDirectlyConnected {
				pulseAnimation = true
			}
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(accessibilityDescription)
	}
}

struct DefaultIcon: View {
	let systemName: String
	
	var body: some View {
		Image(systemName: systemName)
			.symbolRenderingMode(.hierarchical)
			.font(.callout)
	}
}

struct IconAndText: View {
	let systemName: String
	var imageColor: Color?
	var renderingMode: SymbolRenderingMode = .hierarchical
	let text: String
	var textColor: Color = .gray
	
	@ViewBuilder
	var image: some View {
		if let color = imageColor {
			Image(systemName: systemName)
				.foregroundColor(color)
		} else {
			Image(systemName: systemName)
		}
	}
	
	var body: some View {
		HStack {
			image
				.font(.callout)
				.symbolRenderingMode(renderingMode)
				.frame(width: 30)
			Text(text)
				.font(UIDevice.current.userInterfaceIdiom == .phone ? .callout : .caption)
				.foregroundColor(textColor)
				.allowsTightening(true)
		}
	}
}

// MARK: - Mini Map Thumbnail
struct MiniMapThumbnail: View {
	let node: NodeInfoEntity
	let locationData: (PositionEntity, CLLocation)?

	@State private var position: MapCameraPosition = .automatic
	@State private var isPulsing = false

	var body: some View {
		if let (lastPosition, myCoord) = locationData,
		   let nodeCoordinate = lastPosition.nodeCoordinate {

			ZStack(alignment: .topTrailing) {
				// Mini Map
				Map(position: $position) {
					// My location
					Annotation("You", coordinate: myCoordinate) {
						Circle()
							.fill(Color.blue)
							.frame(width: 10, height: 10)
							.overlay(
								Circle()
									.stroke(Color.white, lineWidth: 2)
							)
					}
					.annotationTitles(.hidden)

					// Node location with pulsing effect
					Annotation(node.user?.shortName ?? "?", coordinate: nodeCoordinate) {
						ZStack {
							// Pulsing ring
							Circle()
								.stroke(Color.green, lineWidth: 2)
								.frame(width: 20, height: 20)
								.scaleEffect(isPulsing ? 1.5 : 1.0)
								.opacity(isPulsing ? 0.0 : 0.6)
								.animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: isPulsing)

							// Node pin
							Circle()
								.fill(Color.green)
								.frame(width: 12, height: 12)
								.overlay(
									Circle()
										.stroke(Color.white, lineWidth: 2)
								)
						}
					}
					.annotationTitles(.hidden)

					// Line between locations
					MapPolyline(coordinates: [myCoordinate, nodeCoordinate])
						.stroke(Color.blue.opacity(0.5), lineWidth: 2)
				}
				.mapStyle(.standard(elevation: .flat))
				.mapControls {
					// No controls for thumbnail
				}
				.disabled(true) // Make it non-interactive
				.frame(height: 80)
				.cornerRadius(8)
				.onAppear {
					isPulsing = true
					// Set camera to show both points
					let midLat = (myCoordinate.latitude + nodeCoordinate.latitude) / 2
					let midLon = (myCoordinate.longitude + nodeCoordinate.longitude) / 2
					let latDelta = abs(myCoordinate.latitude - nodeCoordinate.latitude) * 2.5
					let lonDelta = abs(myCoordinate.longitude - nodeCoordinate.longitude) * 2.5

					position = .region(MKCoordinateRegion(
						center: CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
						span: MKCoordinateSpan(
							latitudeDelta: max(latDelta, 0.01),
							longitudeDelta: max(lonDelta, 0.01)
						)
					))
				}

				// Distance badge
				let nodeCoord = CLLocation(latitude: nodeCoordinate.latitude, longitude: nodeCoordinate.longitude)
				let metersAway = nodeCoord.distance(from: myCoord)
				HStack(spacing: 4) {
					Image(systemName: "location.fill")
						.font(.caption2)
					DistanceText(meters: metersAway)
						.font(.caption2)
						.fontWeight(.semibold)
				}
				.padding(4)
				.background(Color.black.opacity(0.7))
				.foregroundColor(.white)
				.cornerRadius(6)
				.padding(6)
			}
		}
	}

	private var myCoordinate: CLLocationCoordinate2D {
		if let myCoord = locationData?.1 {
			return myCoord.coordinate
		}
		return LocationsHandler.DefaultLocation
	}
}

// MARK: - Quick Stats Panel
struct QuickStatsPanel: View {
	let node: NodeInfoEntity
	let locationData: (PositionEntity, CLLocation)?
	let modemPreset: ModemPresets

	var body: some View {
		HStack(spacing: 16) {
			// SNR
			if node.snr != 0 && !node.viaMqtt {
				VStack(alignment: .center, spacing: 2) {
					Image(systemName: "waveform")
						.font(.caption2)
						.foregroundColor(getSnrColor(snr: node.snr, preset: modemPreset))
					Text("\(String(format: "%.1f", node.snr))dB")
						.font(.caption2)
						.fontWeight(.semibold)
						.foregroundColor(getSnrColor(snr: node.snr, preset: modemPreset))
				}
				.frame(maxWidth: .infinity)
			}

			// Battery
			if let battery = node.latestDeviceMetrics?.batteryLevel, battery > 0 {
				VStack(alignment: .center, spacing: 2) {
					Image(systemName: battery > 100 ? "bolt.fill" : battery > 75 ? "battery.100" : battery > 50 ? "battery.75" : battery > 25 ? "battery.50" : "battery.25")
						.font(.caption2)
						.foregroundColor(battery > 100 ? .green : battery > 25 ? .primary : .red)
					Text("\(min(battery, 100))%")
						.font(.caption2)
						.fontWeight(.semibold)
				}
				.frame(maxWidth: .infinity)
			}

			// Distance
			if let (lastPosition, myCoord) = locationData {
				let nodeCoord = CLLocation(latitude: lastPosition.nodeCoordinate!.latitude, longitude: lastPosition.nodeCoordinate!.longitude)
				let metersAway = nodeCoord.distance(from: myCoord)
				VStack(alignment: .center, spacing: 2) {
					Image(systemName: "location.fill")
						.font(.caption2)
						.foregroundColor(.blue)
					DistanceText(meters: metersAway)
						.font(.caption2)
						.fontWeight(.semibold)
				}
				.frame(maxWidth: .infinity)
			}

			// Hops
			if node.hopsAway > 0 {
				VStack(alignment: .center, spacing: 2) {
					Image(systemName: "hare.fill")
						.font(.caption2)
						.foregroundColor(.orange)
					Text("\(node.hopsAway) hops")
						.font(.caption2)
						.fontWeight(.semibold)
				}
				.frame(maxWidth: .infinity)
			}
		}
		.padding(.vertical, 8)
		.padding(.horizontal, 12)
		.background(Color.black.opacity(0.03))
		.cornerRadius(8)
	}
}

// MARK: - Activity Timeline Sparkline
struct ActivityTimeline: View {
	let node: NodeInfoEntity
	private let barCount = 24 // 24 hours

	// Get activity data for the last 24 hours
	private var activityData: [TimeInterval] {
		var hours: [TimeInterval] = []
		let now = Date()

		// Get positions in last 24h
		if let positions = node.positions?.array as? [PositionEntity] {
			let recentPositions = positions.filter { position in
				guard let time = position.time else { return false }
				return now.timeIntervalSince(time) <= 24 * 3600
			}

			// Group by hour
			for i in 0..<barCount {
				let hourStart = now.addingTimeInterval(-Double(i + 1) * 3600)
				let hourEnd = now.addingTimeInterval(-Double(i) * 3600)

				let count = recentPositions.filter { position in
					guard let time = position.time else { return false }
					return time >= hourStart && time < hourEnd
				}.count

				hours.append(Double(count))
			}
		}

		return hours.reversed()
	}

	private func colorForActivity(value: TimeInterval, maxValue: TimeInterval) -> Color {
		if maxValue == 0 { return .gray.opacity(0.3) }

		let ratio = value / maxValue
		if ratio > 0.7 { return .green }
		if ratio > 0.4 { return .orange }
		if ratio > 0 { return .yellow }
		return .gray.opacity(0.3)
	}

	var body: some View {
		let maxValue = activityData.max() ?? 1

		HStack(spacing: 2) {
			Image(systemName: "chart.bar.fill")
				.font(.caption2)
				.foregroundColor(.secondary)
				.frame(width: 20)

			GeometryReader { geometry in
				HStack(spacing: 1) {
					ForEach(0..<barCount, id: \.self) { index in
						let value = index < activityData.count ? activityData[index] : 0
						let height = maxValue > 0 ? (value / maxValue) * geometry.size.height : 2

						RoundedRectangle(cornerRadius: 1)
							.fill(colorForActivity(value: value, maxValue: maxValue))
							.frame(height: max(height, 2))
							.frame(maxHeight: .infinity, alignment: .bottom)
					}
				}
			}
			.frame(height: 20)
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 4)
	}
}

#Preview {
	VStack(alignment: .leading) {
		IconAndText(systemName: "antenna.radiowaves.left.and.right.circle.fill", text: "foo")
		IconAndText(systemName: "antenna.radiowaves.left.and.right.circle", text: "bar")
		NodeListItem(node: {
			let context = PersistenceController.preview.container.viewContext
			let nodeInfo = NodeInfoEntity(context: context)
			let user = UserEntity(context: context)
			user.longName = "Test User"
			user.shortName = "TU"
			nodeInfo.user = user
			return nodeInfo
		}(), isDirectlyConnected: true, connectedNode: 0, modemPreset: .longFast)
	}
}
