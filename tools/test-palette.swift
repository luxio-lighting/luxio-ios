import SwiftUI

@main struct PaletteTest {
    static func main() {
        let red = LightPalette(channels: [[255, 0, 0, 0, 0, 0]])
        let blue = LightPalette(channels: [[0, 0, 255, 0, 0, 0]])
        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            var delta = blue - red; delta.scale(by: fraction)
            let frame = red + delta
            for index in stride(from: 0, to: frame.components.count, by: 3) {
                precondition(abs(frame.components[index] - (1 - fraction)) < 1e-10)
                precondition(frame.components[index + 1] == 0)
                precondition(abs(frame.components[index + 2] - fraction) < 1e-10)
                precondition(abs(frame.components[index] + frame.components[index + 2] - 1) < 1e-10,
                             "Transition must mix the colors without exposing the background")
            }
        }
        // Different stop counts must retain a common interpolation grid.
        let stops = LightPalette(channels: [[255, 0, 0, 0, 0, 0], [0, 255, 0, 0, 0, 0], [0, 0, 255, 0, 0, 0]])
        precondition(stops.components.count == red.components.count)
        precondition(Array(stops.components[96..<99]) == [0, 1, 0])
        var delta = stops - red; delta.scale(by: 0.5)
        let halfway = red + delta
        precondition(Array(halfway.components[96..<99]) == [0.5, 0.5, 0])
        // An interrupted transition continues from its current displayed colors.
        delta = blue - halfway; delta.scale(by: 0.5)
        precondition(Array((halfway + delta).components[96..<99]) == [0.25, 0.25, 0.5])
        let warm = LightPalette(channels: [[0, 0, 0, 0, 255, 0]])
        precondition(Array(warm.components[0..<3]) == [1, 0.73, 0.4])
        precondition(LightPalette.zero.magnitudeSquared == 0)
        print("PASS: direct RGB mixing, changing stop counts, interrupted transitions and white-channel previews")
    }
}
