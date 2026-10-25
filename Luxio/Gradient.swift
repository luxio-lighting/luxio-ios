import Foundation

enum LightMode: String, CaseIterable, Identifiable {
    case color = "Color", gradient = "Gradient", animation = "Animation"
    var id: String { rawValue }
}

struct GradientPoint: Identifiable, Codable, Equatable {
    var id = UUID()
    var hue: Double = 0
    var saturation: Double = 1
    var white = false
    var temperature: Double = 0.5
    var whiteX: Double?
    var originalChannels: [Int]?

    init(hue: Double = 0, saturation: Double = 1, white: Bool = false, temperature: Double = 0.5) {
        self.hue = hue; self.saturation = saturation; self.white = white; self.temperature = temperature
    }
    init(channels: [Int]) {
        originalChannels = channels
        if channels.dropFirst(3).contains(where: { $0 > 0 }) {
            white = true
            temperature = Double(channels[5]) / Double(max(channels[4] + channels[5], 1))
            return
        }
        let r = Double(channels[0]) / 255, g = Double(channels[1]) / 255, b = Double(channels[2]) / 255
        let high = max(r, g, b), low = min(r, g, b), delta = high - low
        saturation = high == 0 ? 0 : delta / high
        if delta == 0 { hue = 0 }
        else if high == r { hue = ((g - b) / delta / 6 + 1).truncatingRemainder(dividingBy: 1) }
        else if high == g { hue = ((b - r) / delta + 2) / 6 }
        else { hue = ((r - g) / delta + 4) / 6 }
    }
    // Normalized wheel coordinates: center (0,0), radius 1, red at -120°.
    mutating func move(x: Double, y: Double) {
        originalChannels = nil
        if white {
            let vertical = min(max(y, -1), 1)
            temperature = (vertical + 1) / 2
            let limit = sqrt(max(0, 1 - vertical * vertical))
            whiteX = min(max(x, -limit), limit)
        }
        else {
            saturation = min(hypot(x, y), 1)
            hue = (atan2(y, x) / (2 * .pi) + 1 + 1.0 / 3).truncatingRemainder(dividingBy: 1)
        }
    }
    func channels(strip: String) -> [Int] {
        if let originalChannels { return originalChannels }
        if white {
            if strip == "WS2805" {
                let cool = Int((temperature * 255).rounded())
                return [0, 0, 0, 0, 255 - cool, cool]
            }
            if (strip == "WS2814" || strip == "SK6812") { return [0, 0, 0, 255, 0, 0] }
        }
        let h = hue * 6, sector = Int(h) % 6, fraction = h - floor(h)
        let low = 1 - saturation, down = 1 - fraction * saturation, up = 1 - (1 - fraction) * saturation
        let rgb: [Double]
        switch sector {
        case 0: rgb = [1, up, low]
        case 1: rgb = [down, 1, low]
        case 2: rgb = [low, 1, up]
        case 3: rgb = [low, down, 1]
        case 4: rgb = [up, low, 1]
        default: rgb = [1, low, down]
        }
        return rgb.map { Int(($0 * 255).rounded()) } + [0, 0, 0]
    }
}

struct CustomGradient: Codable, Equatable {
    var points: [GradientPoint]
    func proto(strip: String, name: String = "") throws -> Proto {
        guard (2...8).contains(points.count) else { throw LuxioError.message("A gradient needs 2–8 points") }
        var result = Proto(); result.string(2, name)
        for point in points {
            var color = Proto()
            for (i, value) in point.channels(strip: strip).enumerated() { color.uint(i + 1, UInt64(value)) }
            result.data(3, color.bytes)
        }
        let metadata = try JSONEncoder().encode(self)
        guard metadata.count <= 2048 else { throw LuxioError.message("Gradient editor data is too large") }
        result.data(4, metadata)
        return result
    }
    init(points: [GradientPoint]) { self.points = points }
    init?(fields: [Int: [Data]], strip: String) {
        guard let entries = fields[3], (2...8).contains(entries.count) else { return nil }
        var channels: [[Int]] = []
        for entry in entries {
            guard let color = try? Proto.decode(entry) else { return nil }
            let values = (1...6).map { color.number($0) }
            guard values.allSatisfy({ (0...255).contains($0) }) else { return nil }
            channels.append(values)
        }
        if let data = fields[4]?.first, let document = try? JSONDecoder().decode(Self.self, from: data),
           document.points.count == channels.count, Set(document.points.map(\.id)).count == document.points.count,
           document.points.allSatisfy({ (0...1).contains($0.hue) && (0...1).contains($0.saturation) && (0...1).contains($0.temperature) && ($0.whiteX == nil || (-1...1).contains($0.whiteX!)) }),
           document.points.map({ $0.channels(strip: strip) }) == channels {
            self = document
        } else { points = channels.map { GradientPoint(channels: $0) } }
    }
}
