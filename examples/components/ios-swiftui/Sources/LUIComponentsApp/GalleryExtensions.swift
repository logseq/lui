import LUIAppleBackend
import MapKit
import SwiftUI

@MainActor
func galleryExtensionRegistry() throws -> LUIAppleExtensionRegistry {
    let registry = LUIAppleExtensionRegistry()
    try registry.register(
        LUIAppleExtension(
            identifier: "apple-map",
            fingerprint: "lui-extension-v1|9:apple-map|profiles:ios/swiftui,macos/swiftui|standard-children:0|children:16:apple-map-marker|properties:14:latitude-delta:float:required:none,15:longitude-delta:float:required:none,8:latitude:float:required:none,9:longitude:float:required:none|events:",
            childIdentifiers: ["apple-map-marker"],
            properties: [
                .init(name: "latitude", kind: .double, isRequired: true),
                .init(name: "longitude", kind: .double, isRequired: true),
                .init(name: "latitude-delta", kind: .double, isRequired: true),
                .init(name: "longitude-delta", kind: .double, isRequired: true),
            ]
        ) { context in
            AnyView(GalleryMap(context: context))
        }
    )
    try registry.register(
        LUIAppleExtension(
            identifier: "apple-map-marker",
            fingerprint: "lui-extension-v1|16:apple-map-marker|profiles:ios/swiftui,macos/swiftui|standard-children:0|children:|properties:5:title:string:required:none,8:latitude:float:required:none,9:longitude:float:required:none|events:",
            properties: [
                .init(name: "title", kind: .string, isRequired: true),
                .init(name: "latitude", kind: .double, isRequired: true),
                .init(name: "longitude", kind: .double, isRequired: true),
            ]
        ) { _ in
            AnyView(EmptyView())
        }
    )
    return registry
}

@MainActor
private struct GalleryMap: View {
    let context: LUIAppleExtensionViewContext

    var body: some View {
        Map(initialPosition: .region(region)) {
            ForEach(context.childIDs, id: \.self) { childID in
                Marker(
                    markerTitle(childID),
                    coordinate: markerCoordinate(childID)
                )
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(minHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityIdentifier("native-mapkit-map")
    }

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: doubleProperty("latitude"),
                longitude: doubleProperty("longitude")
            ),
            span: MKCoordinateSpan(
                latitudeDelta: doubleProperty("latitude-delta"),
                longitudeDelta: doubleProperty("longitude-delta")
            )
        )
    }

    private func markerTitle(_ childID: Int) -> String {
        guard case let .string(value) = context.childProperty(node: childID, "title")
        else { return "Marker" }
        return value
    }

    private func markerCoordinate(_ childID: Int) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: childDoubleProperty(childID, "latitude"),
            longitude: childDoubleProperty(childID, "longitude")
        )
    }

    private func doubleProperty(_ name: String) -> Double {
        guard case let .double(value) = context.property(name) else { return 0 }
        return value
    }

    private func childDoubleProperty(_ childID: Int, _ name: String) -> Double {
        guard case let .double(value) = context.childProperty(node: childID, name)
        else { return 0 }
        return value
    }
}
