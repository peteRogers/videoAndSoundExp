import SwiftUI

struct PlaneView: View {
    @State var model: PlaneModel

    var body: some View {
        VStack(spacing: 16) {
            Text(model.statusText)

            if let plane = model.selected,
               let lat = plane.lat,
               let lon = plane.lon {

                PlaneDirectionCanvas(
                    myLat: model.myLatitude,
                    myLon: model.myLongitude,
                    planeLat: lat,
                    planeLon: lon
                )
                .frame(width: 300, height: 300)

                Text("Flight: \(plane.flight ?? "Unknown")")
                Text("Plane lat: \(lat)")
                Text("Plane lon: \(lon)")
                if let distance = model.selectedDistanceMeters {
                    Text("Distance: \(distance / 1000, specifier: "%.1f") km")
                }

                let bearing = bearingDegrees(
                    fromLat: model.myLatitude,
                    lon: model.myLongitude,
                    toLat: lat,
                    lon: lon
                )

                Text("Bearing: \(bearing, specifier: "%.1f")°")
            } else {
                Text("No plane with position")
                    .frame(width: 300, height: 300)
                    .background(.gray.opacity(0.1))
            }

            if let lastUpdated = model.lastUpdated {
                Text("Updated: \(lastUpdated.formatted(date: .omitted, time: .standard))")
            }
        }
        .padding()
        .onAppear {
            model.startRefreshing()
        }
        .onDisappear {
            model.stopRefreshing()
        }
    }
}
