import Foundation

@main struct GradientTest {
    static func main() throws {
        var point = GradientPoint()
        point.move(x: -0.5, y: -sqrt(3) / 2)
        precondition(point.channels(strip: "WS2805") == [255, 0, 0, 0, 0, 0])
        point.move(x: 0, y: 0)
        precondition(point.channels(strip: "WS2812") == [255, 255, 255, 0, 0, 0])
        point.move(x: 30, y: 30)
        precondition(point.saturation == 1)
        for rgb in [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255], [255, 128, 90]] {
            let recovered = GradientPoint(channels: rgb + [0, 0, 0])
            precondition(recovered.channels(strip: "WS2812") == rgb + [0, 0, 0])
        }
        var warm = GradientPoint(white: true, temperature: 0)
        precondition(warm.channels(strip: "WS2805") == [0, 0, 0, 0, 255, 0])
        warm.move(x: 0, y: 8)
        precondition(warm.channels(strip: "WS2805") == [0, 0, 0, 0, 0, 255])
        precondition(warm.channels(strip: "WS2814") == [0, 0, 0, 255, 0, 0])
        precondition(warm.channels(strip: "WS2812").suffix(3) == [0, 0, 0])
        let single = CustomGradient(points: [GradientPoint(hue: 0.2, saturation: 0.5)])
        let pair = CustomGradient(points: [GradientPoint(hue: 0), GradientPoint(hue: 0.65)])
        let mixed = CustomGradient(points: [GradientPoint(hue: 0), GradientPoint(white: true, temperature: 0), GradientPoint(white: true, temperature: 1)])
        let eight = CustomGradient(points: (0..<8).map { GradientPoint(hue: Double($0) / 8, saturation: Double($0 + 1) / 8) })
        var fixtures: [[String: Any]] = []
        for (name, gradient) in [("single", single), ("two-color", pair), ("mixed-whites", mixed), ("eight-color", eight)] {
            for strip in ["WS2805", "WS2814", "WS2812"] {
                let source = try gradient.source(strip: strip)
                precondition(CustomGradient(source: source) == gradient)
                fixtures.append(["name": name, "strip": strip, "source": source, "stops": gradient.points.map { $0.channels(strip: strip) }])
            }
        }
        precondition(CustomGradient(source: "-- unrelated script") == nil)
        precondition(CustomGradient(source: "-- luxio-gradient-v1:{\"points\":[]}") == nil)
        let invalid = CustomGradient(points: [GradientPoint(hue: 10)])
        let invalidSource = try invalid.source(strip: "WS2812")
        precondition(CustomGradient(source: invalidSource) == nil)
        let duplicate = CustomGradient(points: [point, point])
        let duplicateSource = try duplicate.source(strip: "WS2812")
        precondition(CustomGradient(source: duplicateSource) == nil)
        print(String(data: try JSONSerialization.data(withJSONObject: fixtures), encoding: .utf8)!)
    }
}
