import Foundation

struct LightPreset: Identifiable, Encodable {
    let name: String
    let colors: [[Int]]
    var isGradient = false
    var id: String { name }
    static let all: [LightPreset] = [
        .init(name: "Rainbow", colors: [[255, 0, 0], [255, 220, 0], [0, 220, 80], [0, 120, 255], [160, 0, 255]]),
        .init(name: "Colorloop", colors: [[255, 40, 90], [130, 40, 255], [0, 200, 255]]),
        .init(name: "Aurora", colors: [[130, 70, 255], [0, 180, 160], [75, 30, 160]]),
        .init(name: "Ember", colors: [[255, 70, 12], [210, 20, 0], [255, 200, 35]]),
        .init(name: "Tidal", colors: [[15, 140, 255], [0, 55, 190], [0, 190, 160]]),
        .init(name: "Sunset", colors: [[255, 110, 20], [255, 35, 110], [105, 30, 255]], isGradient: true),
        .init(name: "Lagoon", colors: [[15, 65, 255], [20, 255, 180]], isGradient: true),
        .init(name: "Peach", colors: [[255, 65, 85], [255, 220, 140]], isGradient: true),
        .init(name: "Northern sky", colors: [[65, 25, 255], [0, 180, 255], [100, 255, 160]], isGradient: true)
    ]
    var source: String {
        if isGradient {
            let stops = colors.map { "{\($0.map(String.init).joined(separator: ","))}" }.joined(separator: ",")
            return """
            function setup()
              local stops = {\(stops)}
              local count = luxio_get_pixel_count()
              for i = 0, count - 1 do
                local position = i / math.max(count - 1, 1) * (#stops - 1)
                local segment = math.min(math.floor(position) + 1, #stops - 1)
                local t = position - (segment - 1)
                local a, b = stops[segment], stops[segment + 1]
                luxio_set_pixel_color(i,
                  math.floor(a[1] + (b[1] - a[1]) * t + 0.5),
                  math.floor(a[2] + (b[2] - a[2]) * t + 0.5),
                  math.floor(a[3] + (b[3] - a[3]) * t + 0.5))
              end
            end
            function loop() end
            """
        }
        if name == "Rainbow" || name == "Colorloop" {
            return """
            function setup() end
            function loop()
              local count = luxio_get_pixel_count()
              local time = luxio_millis() / 20000
              for i = 0, count - 1 do
                local h = (time\(name == "Rainbow" ? " + i / count" : "")) % 1 * 6
                local sector = math.floor(h)
                local up = math.floor((h - sector) * 255)
                local down = 255 - up
                local r, g, b = 0, 0, 0
                if sector == 0 then r, g = 255, up
                elseif sector == 1 then r, g = down, 255
                elseif sector == 2 then g, b = 255, up
                elseif sector == 3 then g, b = down, 255
                elseif sector == 4 then r, b = up, 255
                else r, b = 255, down end
                luxio_set_pixel_color(i, r, g, b)
              end
            end
            """
        }
        let rgb = colors[0]
        return """
        function setup() end
        function loop()
          for i = 0, luxio_get_pixel_count() - 1 do
            local t = 0.35 + 0.65 * (math.sin(i / 8 + luxio_millis() / 1800) + 1) / 2
            luxio_set_pixel_color(i, math.floor(\(rgb[0]) * t), math.floor(\(rgb[1]) * t), math.floor(\(rgb[2]) * t))
          end
        end
        """
    }
}
