import SwiftUI

// A fixed sampling grid lets SwiftUI interpolate RGB values even when the
// old and new palettes have different numbers of stops. Every frame is opaque.
struct LightPalette: VectorArithmetic {
    var components: [Double]
    static let zero = LightPalette(components: Array(repeating: 0, count: 65 * 3))

    init(components: [Double]) { self.components = components }
    init(channels: [[Int]]) {
        let colors: [[Double]] = channels.isEmpty ? [[0.25, 0.205, 0.225]] : channels.map { c in
            [min(1, (Double(c[0] + c[3] + c[4]) + Double(c[5]) * 0.8) / 255),
             min(1, (Double(c[1] + c[3]) + Double(c[4]) * 0.73 + Double(c[5]) * 0.9) / 255),
             min(1, (Double(c[2] + c[3]) + Double(c[4]) * 0.4 + Double(c[5])) / 255)]
        }
        components = []
        for sample in 0...64 {
            let position = Double(sample) / 64 * Double(colors.count - 1)
            let left = Int(position), right = min(left + 1, colors.count - 1)
            let fraction = position - Double(left)
            for channel in 0..<3 {
                components.append(colors[left][channel] * (1 - fraction) + colors[right][channel] * fraction)
            }
        }
    }
    static func + (lhs: Self, rhs: Self) -> Self {
        Self(components: zip(lhs.components, rhs.components).map { $0 + $1 })
    }
    static func - (lhs: Self, rhs: Self) -> Self {
        Self(components: zip(lhs.components, rhs.components).map { $0 - $1 })
    }
    mutating func scale(by rhs: Double) {
        for index in components.indices { components[index] *= rhs }
    }
    var magnitudeSquared: Double { components.reduce(0) { $0 + $1 * $1 } }
}

struct LightPaletteGradient: View, Animatable {
    var palette: LightPalette
    var startPoint: UnitPoint
    var endPoint: UnitPoint
    var animatableData: LightPalette {
        get { palette }
        set { palette = newValue }
    }
    var body: some View {
        LinearGradient(colors: stride(from: 0, to: palette.components.count, by: 3).map { index in
            Color(red: palette.components[index], green: palette.components[index + 1], blue: palette.components[index + 2])
        }, startPoint: startPoint, endPoint: endPoint)
    }
}

struct LightBackdrop: View {
    let channels: [[Int]]
    var duration: Double = 0.4
    var startPoint: UnitPoint = .leading
    var endPoint: UnitPoint = .trailing
    var body: some View {
        LightPaletteGradient(palette: LightPalette(channels: channels), startPoint: startPoint, endPoint: endPoint)
            .animation(duration == 0 ? nil : .easeInOut(duration: duration), value: channels)
    }
}
