//
//  TraceRouteLog.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 12/7/23.
//

import SwiftUI
import CoreData
import OSLog
import MapKit

struct TraceRouteLog: View {
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
	@ObservedObject var locationsHandler = LocationsHandler.shared
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	@State private var isPresentingClearLogConfirm: Bool = false
	@State var isExporting = false
	@State var exportString = ""
	@ObservedObject var node: NodeInfoEntity
	@State private var selectedRoute: TraceRouteEntity?
	// Map Configuration
	@Namespace var mapScope
	@State var mapStyle: MapStyle = MapStyle.standard(elevation: .realistic, emphasis: MapStyle.StandardEmphasis.muted, pointsOfInterest: .all, showsTraffic: true)
	@State var position = MapCameraPosition.automatic
	let distanceFormatter = MKDistanceFormatter()
	/// State for the circle of routes
	var modemPreset: ModemPresets = ModemPresets(rawValue: UserDefaults.modemPreset) ?? ModemPresets.longFast
	@State private var indexes: Int = 0
	@State var angle: Angle = .zero
	@State var animation: Animation?

	var body: some View {
		HStack(alignment: .top) {
			VStack {
				// Statistics Header
				if let routes = node.traceRoutes?.array as? [TraceRouteEntity], !routes.isEmpty {
					VStack(spacing: 8) {
						Text("Statistics")
							.font(.headline)
							.frame(maxWidth: .infinity, alignment: .leading)
							.padding(.horizontal)
							.padding(.top, 8)

						let successfulRoutes = routes.filter { $0.response }
						let successCount = routes.filter { $0.response }.count
						let totalSent = routes.filter { $0.sent }.count
						let successRate = totalSent > 0 ? (Double(successCount) / Double(totalSent)) * 100 : 0
						let avgHops = successfulRoutes.isEmpty ? 0 : Double(successfulRoutes.reduce(0) { $0 + $1.hopsTowards }) / Double(successfulRoutes.count)
						let allHops = successfulRoutes.flatMap { ($0.hops?.array as? [TraceRouteHopEntity]) ?? [] }
						let avgSnr = allHops.isEmpty ? 0 : Double(allHops.reduce(0.0) { $0 + Double($1.snr) }) / Double(allHops.count)

						HStack(spacing: 16) {
							// Success Rate
							VStack(alignment: .leading, spacing: 2) {
								Text("Success Rate")
									.font(.caption2)
									.foregroundStyle(.secondary)
								Text("\(Int(successRate))%")
									.font(.title3)
									.fontWeight(.semibold)
									.foregroundStyle(successRate >= 80 ? .green : (successRate >= 50 ? .orange : .red))
							}

							Divider()
								.frame(height: 40)

							// Average Hops
							VStack(alignment: .leading, spacing: 2) {
								Text("Avg Hops")
									.font(.caption2)
									.foregroundStyle(.secondary)
								Text(String(format: "%.1f", avgHops))
									.font(.title3)
									.fontWeight(.semibold)
							}

							Divider()
								.frame(height: 40)

							// Average SNR
							VStack(alignment: .leading, spacing: 2) {
								Text("Avg SNR")
									.font(.caption2)
									.foregroundStyle(.secondary)
								Text(String(format: "%.1f dB", avgSnr))
									.font(.title3)
									.fontWeight(.semibold)
									.foregroundStyle(avgSnr >= 5 ? .green : (avgSnr >= 0 ? .orange : .red))
							}

							Spacer()
						}
						.padding(.horizontal)
						.padding(.bottom, 8)
					}
					.background(Color(.systemGray6))
					.cornerRadius(8)
					.padding(.horizontal, 8)
					.padding(.top, 8)
				}

				VStack {
					List(node.traceRoutes?.reversed() as? [TraceRouteEntity] ?? [], id: \.self, selection: $selectedRoute) { route in
						HStack {
							Label {
								VStack(alignment: .leading, spacing: 4) {
									// Main route info
									if route.response && route.hopsTowards == route.hopsBack {
										let hopString = String(localized: "\(route.hopsTowards) Hops")
										Text(hopString)
											.font(.body)
											.fontWeight(.semibold)
									} else if route.response {
										let hopTowardsString = String(localized: "\(route.hopsTowards) → \(route.hopsBack) Hops")
										Text(hopTowardsString)
											.font(.body)
											.fontWeight(.semibold)
									} else if route.sent {
										Text("Waiting for response...")
											.font(.body)
											.foregroundStyle(.orange)
									} else {
										Text("Not Sent")
											.font(.body)
											.foregroundStyle(.red)
									}

									// Time information
									HStack(spacing: 8) {
										if let sentTime = route.time {
											Text(sentTime.formatted(date: .omitted, time: .shortened))
												.font(.caption2)
												.foregroundStyle(.secondary)
										}

										// Duration if response received
										if route.response, let responseHop = (route.hops?.array as? [TraceRouteHopEntity])?.first, let responseTime = responseHop.time, let sentTime = route.time {
											let duration = responseTime.timeIntervalSince(sentTime)
											Text("• \(String(format: "%.1fs", duration))")
												.font(.caption2)
												.foregroundStyle(.secondary)
										}
									}
								}
							} icon: {
								ZStack {
									if route.response {
										Image(systemName: route.hopsTowards == 0 && route.response ? "person.line.dotted.person" : "point.3.connected.trianglepath.dotted")
											.symbolRenderingMode(.hierarchical)
											.foregroundStyle(.green)
									} else if route.sent {
										Image(systemName: "signpost.right.and.left")
											.symbolRenderingMode(.hierarchical)
											.foregroundStyle(.orange)
									} else {
										Image(systemName: "person.slash")
											.symbolRenderingMode(.hierarchical)
											.foregroundStyle(.red)
									}
								}
							}

							Spacer()

							// Status badge
							if route.response {
								Image(systemName: "checkmark.circle.fill")
									.foregroundStyle(.green)
									.font(.title3)
							} else if route.sent {
								ProgressView()
									.scaleEffect(0.8)
							}
						}
						.swipeActions {
							Button(role: .destructive) {
								context.delete(route)
								do {
									try context.save()
								} catch let error as NSError {
									Logger.data.error("\(error.localizedDescription, privacy: .public)")
								}
							} label: {
								Label("Delete", systemImage: "trash")
							}
						}
					}
					.listStyle(.plain)
				}
				Divider()
				ScrollView {
					if selectedRoute != nil {
						if selectedRoute?.response ?? false && selectedRoute?.hopsTowards ?? 0 >= 0 {
							Label {
								Text("Route: \(selectedRoute?.routeText ?? "Unknown".localized)")
							} icon: {
								Image(systemName: "signpost.right")
									.symbolRenderingMode(.hierarchical)
							}
							.font(.title3)
							Label {
								Text("Route Back: \(selectedRoute?.routeBackText ?? "Unknown".localized)")
							} icon: {
								Image(systemName: "signpost.left")
									.symbolRenderingMode(.hierarchical)
							}
							.font(.title3)
						} else if !(selectedRoute?.sent ?? true) {
								Label {
									VStack {
										Text("Trace route to \(selectedRoute?.node?.user?.longName ?? "Unknown".localized) was not sent.")
											.font(idiom == .phone ? .body : .largeTitle)
											.fontWeight(.semibold)
										Text("Trace Route was rate limited. You can send a trace route a maximum of once every thirty seconds.")
											.font(idiom == .phone ? .caption : .body)
											.foregroundStyle(.secondary)
											.padding()
									}
								} icon: {
									Image(systemName: "square.and.arrow.up.trianglebadge.exclamationmark")
										.symbolRenderingMode(.hierarchical)
								}
						} else {
							   Label {
								   VStack {
									   Text("Trace route sent to \(selectedRoute?.node?.user?.longName ?? "Unknown".localized)")
										   .font(idiom == .phone ? .body : .largeTitle)
										   .fontWeight(.semibold)
									   Text("A Trace Route was sent, no response has been received.")
										   .font(idiom == .phone ? .caption : .body)
										   .foregroundStyle(.secondary)
										   .padding()
								   }
							   } icon: {
								   Image(systemName: "signpost.right.and.left")
									   .symbolRenderingMode(.hierarchical)
							   }
						}

						// Show map if we have positions
						if selectedRoute?.hasPositions ?? false {
							TraceRouteMapView(traceRoute: selectedRoute!)
						}

						if false {// selectedRoute?.hops?.count ?? 0 >= 3 {
							HStack(alignment: .center) {
								GeometryReader { geometry in
									let size = ((geometry.size.width >= geometry.size.height ? geometry.size.height : geometry.size.width) / 2) - (idiom == .phone ? 45 : 85)
									Spacer()
									TraceRoute(radius: size < 600 ? size : 600, rotation: angle) {
										contents()
									}
									.padding(.leading, idiom == .phone ? 0 : 20)
									Spacer()
								}
								.scaledToFit()
							}
							.onAppear {
								// Set the view rotation animation after the view appeared,
								// to avoid animating initial rotation
								DispatchQueue.main.async {
									indexes = (selectedRoute?.hops?.array.count ?? 0) * 2
									animation = .easeInOut(duration: 1.0)
									withAnimation(.easeInOut(duration: 2.0)) {
										angle = (angle == .degrees(-90) ? .degrees(-90) : .degrees(-90))
									}
								}
							}
							.onTapGesture {
								withAnimation(.easeInOut(duration: 2.0)) {
									angle = (angle == .degrees(-90) ? .degrees(90) : .degrees(-90))
								}
							}
						}
						if selectedRoute?.hasPositions ?? false {
//							Map(position: $position, bounds: MapCameraBounds(minimumDistance: 1, maximumDistance: .infinity), scope: mapScope) {
//								Annotation("You", coordinate: selectedRoute?.coordinate ?? LocationHelper.DefaultLocation) {
//									ZStack {
//										Circle()
//											.fill(Color(.green))
//											.strokeBorder(.white, lineWidth: 3)
//											.frame(width: 15, height: 15)
//									}
//								}
//								.annotationTitles(.automatic)
//								// Direct Trace Route
//								if selectedRoute?.response ?? false && selectedRoute?.hops?.count ?? 0 == 0 {
//									if selectedRoute?.node?.positions?.count ?? 0 > 0, let mostRecent = selectedRoute?.node?.positions?.lastObject as? PositionEntity {
//										let traceRouteCoords: [CLLocationCoordinate2D] = [selectedRoute?.coordinate ?? LocationsHandler.DefaultLocation, mostRecent.coordinate]
//										Annotation(selectedRoute?.node?.user?.shortName ?? "???", coordinate: mostRecent.nodeCoordinate ?? LocationHelper.DefaultLocation) {
//											ZStack {
//												Circle()
//													.fill(Color(.black))
//													.strokeBorder(.white, lineWidth: 3)
//													.frame(width: 15, height: 15)
//											}
//										}
//										let dashed = StrokeStyle(
//											lineWidth: 2,
//											lineCap: .round, lineJoin: .round, dash: [7, 10]
//										)
//										MapPolyline(coordinates: traceRouteCoords)
//											.stroke(.blue, style: dashed)
//									}
//								}
//							}
//							.frame(maxWidth: .infinity, minHeight: 250)
//							if selectedRoute?.response ?? false {
//								VStack {
//									/// Distance
//									if selectedRoute?.node?.positions?.count ?? 0 > 0,
//									   selectedRoute?.coordinate != nil,
//									   let mostRecent = selectedRoute?.node?.positions?.lastObject as? PositionEntity {
//										let startPoint = CLLocation(latitude: selectedRoute?.coordinate?.latitude ?? LocationsHandler.DefaultLocation.latitude, longitude: selectedRoute?.coordinate?.longitude ?? LocationsHandler.DefaultLocation.longitude)
//										if startPoint.distance(from: CLLocation(latitude: LocationsHandler.DefaultLocation.latitude, longitude: LocationsHandler.DefaultLocation.longitude)) > 0.0 {
//											let metersAway = selectedRoute?.coordinate?.distance(from: CLLocationCoordinate2D(latitude: mostRecent.latitude ?? LocationsHandler.DefaultLocation.latitude, longitude: mostRecent.longitude ?? LocationsHandler.DefaultLocation.longitude))
//											Label {
//												Text("distance".localized + ": \(distanceFormatter.string(fromDistance: Double(metersAway ?? 0)))")
//													.foregroundColor(.primary)
//											} icon: {
//												Image(systemName: "lines.measurement.horizontal")
//													.symbolRenderingMode(.hierarchical)
//											}
//										}
//									}
//								}
//							}
							Spacer()
								.padding(.bottom, 125)
						}
					} else {
						ContentUnavailableView("Select a Trace Route", systemImage: "signpost.right.and.left")
					}
				}
				.edgesIgnoringSafeArea(.bottom)
			}
			.navigationTitle("Trace Route Log")
		}
		.navigationBarItems(trailing:
								ZStack {
			ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
		})
	}
	@ViewBuilder func contents(animation: Animation? = nil) -> some View {
		ForEach(0..<indexes, id: \.self) { idx in
			TraceRouteComponent(animation: animation) {
				let hops = selectedRoute?.hops?.array as? [TraceRouteHopEntity] ?? [] // getTraceRouteHops(context: PersistenceController.preview.container.viewContext)//
				if idx % 2 == 0 {
					let i = idx / 2
					let snrColor = getSnrColor(snr: hops[i].snr, preset: modemPreset)
					VStack {
						let nodeColor = UIColor(hex: UInt32(truncatingIfNeeded: hops[i].num))
						CircleText(text: String(hops[i].num.toHex().suffix(4)), color: Color(nodeColor), circleSize: idiom == .phone ? 70 : 125)
							Text("\(String(format: "%.2f", hops[i].snr)) dB")
								.font(idiom == .phone ? .caption2 : .headline)
								.foregroundColor(snrColor)
								.allowsTightening(true)
								.fontWeight(.semibold)
					}
				} else {
					let i = (idx - 1) / 2
					let snrColor = getSnrColor(snr: hops[i].snr, preset: modemPreset)
					Image(systemName: "arrowshape.right.fill")
						.resizable()
						.frame(width: idiom == .phone ? 25 : 60, height: idiom == .phone ? 25 : 60)
						.foregroundColor(snrColor.opacity(0.7))
				}
			}
		}
	}
}

func getTraceRouteHops(context: NSManagedObjectContext) -> [TraceRouteHopEntity] {
	///	static let context = PersistenceController.preview.container.viewContext
	var array = [TraceRouteHopEntity]()
	let trh1 = TraceRouteHopEntity(context: context)
	trh1.num = 366311664
	trh1.snr = 12.5
	let trh2 = TraceRouteHopEntity(context: context)
	trh2.num = 3662955168
	trh2.snr = -115.00
	let trh3 = TraceRouteHopEntity(context: context)
	trh3.num = 3663982804
	trh3.snr = 17.5
	let trh4 = TraceRouteHopEntity(context: context)
	trh4.num = 4202719792
	trh4.snr = 7.0
	let trh5 = TraceRouteHopEntity(context: context)
	trh5.num = 603700594
	trh5.snr = 8.9
	let trh6 = TraceRouteHopEntity(context: context)
	trh6.num = 836212501
	trh6.snr = -24.0
	let trh7 = TraceRouteHopEntity(context: context)
	trh7.num = 3663116644
	trh7.snr = -6.0
	let trh8 = TraceRouteHopEntity(context: context)
	trh8.num = 8362955168
	trh8.snr = 7.5
	array.append(trh1)
	array.append(trh2)
	array.append(trh3)
	array.append(trh4)
	array.append(trh5)
	array.append(trh6)
	array.append(trh7)
	array.append(trh8)
	return array
}

// MARK: - Trace Route Map View
struct TraceRouteMapView: View {
	let traceRoute: TraceRouteEntity

	@Namespace var mapScope
	@State private var mapStyle: MapStyle = MapStyle.standard(elevation: .realistic, emphasis: MapStyle.StandardEmphasis.muted, pointsOfInterest: .all, showsTraffic: false)
	@State private var position = MapCameraPosition.automatic
	@State private var animationPhase = false

	var body: some View {
		VStack {
			if traceRoute.hasPositions {
				Map(position: $position, bounds: MapCameraBounds(minimumDistance: 100, maximumDistance: .infinity), scope: mapScope) {

					if let hops = traceRoute.hops?.array as? [TraceRouteHopEntity] {
						let towardsHops = hops.filter { $0.back == false }
						let backHops = hops.filter { $0.back == true }

						// Draw "towards" route (green) with dashed red for unknown hops
						let towardsCoords = towardsHops.compactMap { $0.coordinate }
						ForEach(0..<towardsHops.count, id: \.self) { index in
							if let coord = towardsHops[index].coordinate, index > 0 {
								if let prevCoord = towardsHops[0..<index].last(where: { $0.coordinate != nil })?.coordinate {
									// Check if there's a gap in indices (unknown hop)
									let prevIndex = towardsHops[0..<index].lastIndex(where: { $0.coordinate != nil }) ?? 0
									if index - prevIndex > 1 {
										// Dashed red line for unknown hops
										let dashedStyle = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [8, 4])
										MapPolyline(coordinates: [prevCoord, coord])
											.stroke(.red, style: dashedStyle)
									} else {
										// Solid green line
										MapPolyline(coordinates: [prevCoord, coord])
											.stroke(.green, lineWidth: 3)
									}
								}
							}
						}

						// Draw "back" route (blue) with dashed red for unknown hops
						if !backHops.isEmpty {
							ForEach(0..<backHops.count, id: \.self) { index in
								if let coord = backHops[index].coordinate, index > 0 {
									if let prevCoord = backHops[0..<index].last(where: { $0.coordinate != nil })?.coordinate {
										let prevIndex = backHops[0..<index].lastIndex(where: { $0.coordinate != nil }) ?? 0
										if index - prevIndex > 1 {
											// Dashed red line for unknown hops
											let dashedStyle = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [8, 4])
											MapPolyline(coordinates: [prevCoord, coord])
												.stroke(.red, style: dashedStyle)
										} else {
											// Solid blue line
											MapPolyline(coordinates: [prevCoord, coord])
												.stroke(.blue, lineWidth: 3)
										}
									}
								}
							}
						}

						// Draw markers for towards hops
						ForEach(Array(towardsHops.enumerated()), id: \.offset) { index, hop in
							if let coord = hop.coordinate {
								Annotation(hop.name ?? "Node \(hop.num.toHex())", coordinate: coord) {
									VStack {
										ZStack {
											// Pulsing ring animation
											Circle()
												.stroke(getSnrColor(snr: hop.snr), lineWidth: 3)
												.frame(width: 30, height: 30)
												.scaleEffect(animationPhase ? 1.5 : 1.0)
												.opacity(animationPhase ? 0.0 : 0.6)
												.animation(
													.easeInOut(duration: 1.5)
													.repeatForever(autoreverses: false)
													.delay(Double(index) * 0.3),
													value: animationPhase
												)

											Circle()
												.fill(getSnrColor(snr: hop.snr))
												.strokeBorder(.white, lineWidth: 2)
												.frame(width: 30, height: 30)

											Text("\(index + 1)")
												.font(.caption2)
												.fontWeight(.bold)
												.foregroundColor(.white)
										}

										VStack(spacing: 2) {
											Text(hop.name ?? "Node \(hop.num.toHex())")
												.font(.caption2)
												.padding(4)
												.background(Color.white.opacity(0.9))
												.cornerRadius(4)

											if hop.snr != -32 {
												Text("\(String(format: "%.1f", hop.snr)) dB")
													.font(.caption2)
													.padding(4)
													.background(getSnrColor(snr: hop.snr).opacity(0.9))
													.foregroundColor(.white)
													.cornerRadius(4)
											}
										}
									}
								}
								.annotationTitles(.hidden)
							}
						}

						// Draw markers for back hops (if different from towards)
						ForEach(Array(backHops.enumerated()), id: \.offset) { index, hop in
							if let coord = hop.coordinate {
								// Only show if not already shown in towards
								let alreadyShown = towardsHops.contains(where: {
									$0.coordinate?.latitude == coord.latitude &&
									$0.coordinate?.longitude == coord.longitude
								})
								if !alreadyShown {
									Annotation(hop.name ?? "Node \(hop.num.toHex())", coordinate: coord) {
										VStack {
											ZStack {
												Circle()
													.fill(getSnrColor(snr: hop.snr))
													.strokeBorder(.blue, lineWidth: 2)
													.frame(width: 30, height: 30)

												Text("B\(index + 1)")
													.font(.caption2)
													.fontWeight(.bold)
													.foregroundColor(.white)
											}

											VStack(spacing: 2) {
												Text(hop.name ?? "Node \(hop.num.toHex())")
													.font(.caption2)
													.padding(4)
													.background(Color.white.opacity(0.9))
													.cornerRadius(4)

												if hop.snr != -32 {
													Text("\(String(format: "%.1f", hop.snr)) dB")
														.font(.caption2)
														.padding(4)
														.background(getSnrColor(snr: hop.snr).opacity(0.9))
														.foregroundColor(.white)
														.cornerRadius(4)
												}
											}
										}
									}
									.annotationTitles(.hidden)
								}
							}
						}
					}
				}
				.mapStyle(mapStyle)
				.mapControls {
					MapUserLocationButton()
					MapCompass()
					MapScaleView()
				}
				.frame(height: 400)
				.cornerRadius(12)
				.padding()
			} else {
				ContentUnavailableView(
					"No Position Data",
					systemImage: "map.fill",
					description: Text("Nodes in this trace route don't have known positions")
				)
			}
		}
		.onAppear {
			animationPhase = true
		}
	}

	private func getSnrColor(snr: Float) -> Color {
		// SNR color coding based on signal quality
		if snr >= 10 {
			return .green
		} else if snr >= 5 {
			return .blue
		} else if snr >= 0 {
			return .orange
		} else {
			return .red
		}
	}
}
