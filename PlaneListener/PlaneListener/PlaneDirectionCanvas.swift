//
//  PlaneDirectionCanvas.swift
//  PlaneListener
//
//  Created by student on 09/03/2026.
//

import SwiftUI

struct PlaneDirectionCanvas: View {
    let myLat: Double
    let myLon: Double
    let planeLat: Double
    let planeLon: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            let bearing = bearingDegrees(
                fromLat: myLat,
                lon: myLon,
                toLat: planeLat,
                lon: planeLon
            )

            let distance = distanceMeters(
                fromLat: myLat,
                lon: myLon,
                toLat: planeLat,
                lon: planeLon
            )

            // Convert compass bearing to canvas angle
            // Compass: 0=north, 90=east
            // Canvas: 0=right, 90=down
            let angle = degreesToRadians(bearing - 90)

            // Clamp line length so very distant planes still fit on screen
            let maxRadius = min(size.width, size.height) * 0.4
            let lineLength = min(maxRadius, max(40, distance / 1000))

            let endPoint = CGPoint(
                x: center.x + cos(angle) * lineLength,
                y: center.y + sin(angle) * lineLength
            )

            // Background circle
            let circleRect = CGRect(
                x: center.x - maxRadius,
                y: center.y - maxRadius,
                width: maxRadius * 2,
                height: maxRadius * 2
            )
            context.stroke(
                Path(ellipseIn: circleRect),
                with: .color(.gray.opacity(0.4)),
                lineWidth: 1
            )

            // Direction line
            var line = Path()
            line.move(to: center)
            line.addLine(to: endPoint)
            context.stroke(line, with: .color(.red), lineWidth: 3)

            // Dot for you
            let meRect = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: meRect), with: .color(.blue))

            // Dot for plane direction
            let planeRect = CGRect(x: endPoint.x - 6, y: endPoint.y - 6, width: 12, height: 12)
            context.fill(Path(ellipseIn: planeRect), with: .color(.red))
        }
        .aspectRatio(1, contentMode: .fit)
        .padding()
    }
}
