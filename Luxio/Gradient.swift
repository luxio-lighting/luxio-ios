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

    init(hue: Double = 0, saturation: Double = 1, white: Bool = false, temperature: Double = 0.5) {
        self.hue = hue; self.saturation = saturation; self.white = white; self.temperature = temperature
    }
    init(channels: [Int]) {
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
        if white { temperature = min(max((y + 1) / 2, 0), 1) }
        else {
            saturation = min(hypot(x, y), 1)
            hue = (atan2(y, x) / (2 * .pi) + 1 + 1.0 / 3).truncatingRemainder(dividingBy: 1)
        }
    }
    func channels(strip: String) -> [Int] {
        if white {
            if strip == "WS2805" {
                let cool = Int((temperature * 255).rounded())
                return [0, 0, 0, 0, 255 - cool, cool]
            }
            if strip == "WS2814" { return [0, 0, 0, 255, 0, 0] }
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
    func source(strip: String) throws -> String {
        let metadata = String(data: try JSONEncoder().encode(self), encoding: .utf8)!
        let stops = points.map { "{\($0.channels(strip: strip).map(String.init).joined(separator: ","))}" }.joined(separator: ",")
        let channels = (1...6).map { "math.floor(a[\($0)] + (b[\($0)] - a[\($0)]) * t + 0.5)" }.joined(separator: ",\n      ")
        return """
        -- luxio-gradient-v1:\(metadata)
        function setup()
          local stops = {\(stops)}
          local count = luxio_get_pixel_count()
          for i = 0, count - 1 do
            local position = i / math.max(count - 1, 1) * (#stops - 1)
            local segment = math.max(1, math.min(math.floor(position) + 1, #stops - 1))
            local t = position - (segment - 1)
            local a, b = stops[segment], stops[math.min(segment + 1, #stops)]
            luxio_set_pixel_color(i,
              \(channels))
          end
        end
        function loop() end
        """
    }
    init(points: [GradientPoint]) { self.points = points }
    init?(source: String) {
        let prefix = "-- luxio-gradient-v1:"
        guard let line = source.split(separator: "\n").first, line.hasPrefix(prefix),
              let document = try? JSONDecoder().decode(Self.self, from: Data(line.dropFirst(prefix.count).utf8)),
              (1...8).contains(document.points.count), Set(document.points.map(\.id)).count == document.points.count,
              document.points.allSatisfy({ (0...1).contains($0.hue) && (0...1).contains($0.saturation) && (0...1).contains($0.temperature) }) else { return nil }
        self = document
    }
}
