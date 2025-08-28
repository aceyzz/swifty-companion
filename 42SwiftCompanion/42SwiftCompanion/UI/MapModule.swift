import SwiftUI
import MapKit
import CoreLocation
import UIKit

struct MapSheetModel: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let coordinate: CLLocationCoordinate2D
    let span: MKCoordinateSpan

    var region: MKCoordinateRegion { .init(center: coordinate, span: span) }

    static func == (lhs: MapSheetModel, rhs: MapSheetModel) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class MapRouter: ObservableObject {
    static let shared = MapRouter()
    @Published var sheet: MapSheetModel?

    func presentCoordinate(_ coord: CLLocationCoordinate2D, name: String, subtitle: String? = nil, span: MKCoordinateSpan = .init(latitudeDelta: 0.01, longitudeDelta: 0.01)) {
        sheet = .init(title: name, subtitle: subtitle, coordinate: coord, span: span)
    }

    func presentAddress(_ address: String, name: String? = nil, span: MKCoordinateSpan = .init(latitudeDelta: 0.02, longitudeDelta: 0.02)) {
		Task { @MainActor in
			if let place = try? await Geocoder.geocode(address), let loc = place.location {
				presentCoordinate(loc.coordinate, name: name ?? address, subtitle: address, span: span)
			} else {
				let q = (name?.isEmpty == false ? name! : address)
				if let url = URL(string: "http://maps.apple.com/?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
					_ = await UIApplication.shared.open(url)
				}
			}
		}
	}

    func dismiss() { sheet = nil }
}

@MainActor
enum MapModule {
    static func openAddress(_ address: String, name: String? = nil) {
        MapRouter.shared.presentAddress(address, name: name)
    }

    static func openCoordinate(lat: Double, lon: Double, name: String, subtitle: String? = nil) {
        MapRouter.shared.presentCoordinate(.init(latitude: lat, longitude: lon), name: name, subtitle: subtitle)
    }
}

private enum Geocoder {
    static func geocode(_ address: String) async throws -> CLPlacemark {
        try await withCheckedThrowingContinuation { cont in
            CLGeocoder().geocodeAddressString(address) { placemarks, error in
                if let error {
                    cont.resume(throwing: error)
                } else if let p = placemarks?.first {
                    cont.resume(returning: p)
                } else {
                    cont.resume(throwing: URLError(.badURL))
                }
            }
        }
    }
}

struct MapSheet: View {
    let model: MapSheetModel
    @State private var camera: MapCameraPosition

    init(model: MapSheetModel) {
        self.model = model
        _camera = State(initialValue: .region(model.region))
    }

    var body: some View {
        NavigationStack {
            Map(position: $camera, interactionModes: [.pan, .zoom, .rotate, .pitch]) {
                Marker(model.title, coordinate: model.coordinate)
            }
            .mapControls {
                MapCompass()
                MapPitchToggle()
                MapUserLocationButton()
            }
            .ignoresSafeArea(edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { MapRouter.shared.dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ouvrir dans Plans") { openInMaps() }
                }
            }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: .init(coordinate: model.coordinate))
        item.name = model.title
        item.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: model.region.center),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: model.region.span)
        ])
    }
}
