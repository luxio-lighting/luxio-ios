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
        for rgb in [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 255], [255, 128, 90], [16, 8, 4], [0, 0, 0]] {
            let recovered = GradientPoint(channels: rgb + [0, 0, 0])
            precondition(recovered.channels(strip: "WS2812") == rgb + [0, 0, 0])
        }
        var warm = GradientPoint(white: true, temperature: 0)
        precondition(warm.channels(strip: "WS2805") == [0, 0, 0, 0, 255, 0])
        warm.move(x: 0, y: 8)
        precondition(warm.channels(strip: "WS2805") == [0, 0, 0, 0, 0, 255])
        precondition(warm.channels(strip: "WS2814") == [0, 0, 0, 255, 0, 0])
        precondition(warm.channels(strip: "WS2812").suffix(3) == [0, 0, 0])
        warm.move(x: -0.7, y: 0.4)
        let whiteChannels = warm.channels(strip: "WS2805")
        precondition(warm.whiteX == -0.7 && warm.temperature == 0.7)
        warm.move(x: 0.7, y: 0.4)
        precondition(warm.whiteX == 0.7 && warm.channels(strip: "WS2805") == whiteChannels)
        warm.move(x: 10, y: 0.4)
        precondition(abs(pow(warm.whiteX!, 2) + pow(warm.temperature * 2 - 1, 2) - 1) < 0.000001)
        let movableWhite = CustomGradient(points: [warm, GradientPoint(white: true, temperature: 0)])
        let whiteFields = try Proto.decode(movableWhite.proto(strip: "WS2805").bytes)
        precondition(CustomGradient(fields: whiteFields, strip: "WS2805") == movableWhite)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(warm)) as! [String: Any]
        legacy.removeValue(forKey: "whiteX")
        let legacyPoint = try JSONDecoder().decode(GradientPoint.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(legacyPoint.whiteX == nil && legacyPoint.channels(strip: "WS2805") == whiteChannels)
        let single = CustomGradient(points: [GradientPoint(hue: 0.2, saturation: 0.5)])
        let pair = CustomGradient(points: [GradientPoint(hue: 0), GradientPoint(hue: 0.65)])
        let mixed = CustomGradient(points: [GradientPoint(hue: 0), GradientPoint(white: true, temperature: 0), GradientPoint(white: true, temperature: 1)])
        let eight = CustomGradient(points: (0..<8).map { GradientPoint(hue: Double($0) / 8, saturation: Double($0 + 1) / 8) })
        var fixtures: [[String: Any]] = []
        for (name, gradient) in [("two-color", pair), ("mixed-whites", mixed), ("eight-color", eight)] {
            for strip in ["WS2805", "WS2814", "WS2812"] {
                let bytes = try gradient.proto(strip: strip).bytes
                let fields = try Proto.decode(bytes)
                precondition(CustomGradient(fields: fields, strip: strip) == gradient)
                fixtures.append(["name": name, "strip": strip, "bytes": bytes.base64EncodedString(), "stops": gradient.points.map { $0.channels(strip: strip) }])
            }
        }
        precondition((try? single.proto(strip: "WS2805")) == nil)
        precondition(CustomGradient(fields: [:], strip: "WS2805") == nil)
        var bad = try pair.proto(strip: "WS2805")
        bad.string(4, "invalid JSON")
        let recovered = CustomGradient(fields: try Proto.decode(bad.bytes), strip: "WS2805")!
        precondition(recovered.points.map { $0.channels(strip: "WS2805") } == pair.points.map { $0.channels(strip: "WS2805") })
        print(String(data: try JSONSerialization.data(withJSONObject: fixtures), encoding: .utf8)!)
    }
}
