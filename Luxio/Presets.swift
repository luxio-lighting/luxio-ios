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
        .init(name: "Christmas", colors: [[85, 56, 27], [255, 190, 105]]),
        .init(name: "Knight Rider", colors: [[35, 0, 0], [255, 0, 0]]),
        .init(name: "Fireplace", colors: [[115, 12, 0], [255, 95, 10], [255, 175, 35]]),
        .init(name: "Candle", colors: [[170, 80, 22], [255, 165, 55]]),
        .init(name: "Cyberpunk", colors: [[15, 0, 50], [255, 0, 160], [0, 220, 255]]),
        .init(name: "Sunset", colors: [[255, 110, 20], [255, 35, 110], [105, 30, 255]], isGradient: true),
        .init(name: "Lagoon", colors: [[15, 65, 255], [20, 255, 180]], isGradient: true),
        .init(name: "Peach", colors: [[255, 65, 85], [255, 220, 140]], isGradient: true),
        .init(name: "Northern sky", colors: [[65, 25, 255], [0, 180, 255], [100, 255, 160]], isGradient: true),
        .init(name: "Dawn", colors: [[65, 35, 130], [205, 80, 140], [255, 170, 100], [255, 225, 160]], isGradient: true),
        .init(name: "Golden hour", colors: [[255, 65, 15], [255, 150, 30], [255, 225, 110]], isGradient: true),
        .init(name: "Coral", colors: [[255, 40, 85], [255, 100, 90], [255, 175, 125]], isGradient: true),
        .init(name: "Apricot", colors: [[255, 135, 75], [255, 205, 145], [255, 180, 185]], isGradient: true),
        .init(name: "Rose", colors: [[120, 10, 65], [235, 45, 120], [255, 155, 185]], isGradient: true),
        .init(name: "Lavender", colors: [[90, 55, 185], [165, 125, 255], [240, 185, 255]], isGradient: true),
        .init(name: "Cotton candy", colors: [[255, 140, 205], [195, 150, 255], [115, 210, 255]], isGradient: true),
        .init(name: "Opal", colors: [[120, 235, 210], [160, 195, 255], [230, 170, 245], [255, 210, 175]], isGradient: true),
        .init(name: "Glacier", colors: [[25, 55, 155], [30, 155, 230], [140, 245, 255]], isGradient: true),
        .init(name: "Ocean", colors: [[10, 15, 80], [15, 65, 190], [0, 160, 195]], isGradient: true),
        .init(name: "Reef", colors: [[0, 110, 140], [0, 220, 180], [140, 255, 170]], isGradient: true),
        .init(name: "Forest", colors: [[10, 50, 35], [20, 120, 65], [105, 185, 55]], isGradient: true),
        .init(name: "Meadow", colors: [[35, 145, 90], [140, 220, 90], [245, 240, 135]], isGradient: true),
        .init(name: "Citrus", colors: [[80, 220, 15], [220, 255, 20], [255, 175, 15]], isGradient: true),
        .init(name: "Mango", colors: [[255, 195, 25], [255, 100, 10], [245, 30, 75]], isGradient: true),
        .init(name: "Firelight", colors: [[100, 5, 0], [235, 35, 0], [255, 115, 10], [255, 200, 65]], isGradient: true),
        .init(name: "Ruby", colors: [[65, 0, 45], [165, 5, 65], [255, 35, 85]], isGradient: true),
        .init(name: "Amethyst", colors: [[40, 10, 100], [115, 30, 210], [215, 85, 245]], isGradient: true),
        .init(name: "Nebula", colors: [[20, 35, 150], [105, 20, 210], [225, 25, 160], [255, 90, 115]], isGradient: true),
        .init(name: "Neon", colors: [[0, 225, 255], [65, 65, 255], [225, 0, 255]], isGradient: true)
    ]
    var previewColors: [[Int]] {
        if isGradient { return colors }
        if ["Christmas", "Knight Rider", "Fireplace", "Candle", "Cyberpunk"].contains(name) { return colors }
        if name == "Rainbow" || name == "Colorloop" {
            return [[255, 0, 0], [255, 255, 0], [0, 255, 0], [0, 255, 255], [0, 0, 255], [255, 0, 255]]
        }
        // These animations pulse the first RGB color between 35% and 100%.
        return [colors[0].map { Int(floor(Double($0) * 0.35)) }, colors[0]]
    }
    var source: String {
        if isGradient { return "" }
        let preview = "-- @preview " + previewColors.map { $0.map { String(format: "%02x", $0) }.joined() }.joined(separator: ",") + "\n"
        if name == "Christmas" {
            return preview + """
            -- Soft, independent warm-white twinkles over a steady glow.
            function loop()
              local t = luxio_millis() / 1000
              local sin, floor, max = math.sin, math.floor, math.max
              for i = 0, luxio_get_pixel_count() - 1 do
                local phase = (sin(i * 127.1 + 311.7) * 43758.5453) % 6.28318
                local wave = max(0, sin(t * (0.8 + (i * 0.618034 % 1) * 1.2) + phase))
                local glow = 0.16 + 0.84 * wave ^ 8
                luxio_set_pixel_color(i, floor(255 * glow), floor(190 * glow), floor(105 * glow))
              end
            end
            """
        }
        if name == "Knight Rider" {
            return preview + """
            -- A red scanner with a fading tail, sweeping out and back.
            function loop()
              local count = luxio_get_pixel_count()
              local phase = (luxio_millis() / 1300) % 2
              local direction = phase < 1 and 1 or -1
              local head = (phase < 1 and phase or 2 - phase) * (count - 1)
              local tail = math.max(1, count * 0.1)
              local floor, abs, max, exp = math.floor, math.abs, math.max, math.exp
              for i = 0, count - 1 do
                local distance = (head - i) * direction
                local glow = max(0, 1 - abs(head - i) / 1.5)
                if distance >= 0 then glow = max(glow, 0.7 * exp(-distance / tail)) end
                if count == 1 then glow = 0.35 + 0.65 * (1 + math.cos(phase * math.pi)) / 2 end
                luxio_set_pixel_color(i, floor(255 * glow), 0, 0)
              end
            end
            """
        }
        if name == "Fireplace" {
            return preview + """
            -- Uneven pockets of glowing embers and dancing amber flames.
            function loop()
              local t = luxio_millis() / 1000
              local sin, floor = math.sin, math.floor
              for i = 0, luxio_get_pixel_count() - 1 do
                local heat = 0.5 + 0.22 * sin(t * 2.8 + i * 0.7)
                  + 0.12 * sin(t * 7.1 - i * 1.3) + 0.06 * sin(t * 13.3 + i * 2.1)
                luxio_set_pixel_color(i, floor(120 + 135 * heat), floor(12 + 180 * heat ^ 3), floor(35 * heat ^ 8))
              end
            end
            """
        }
        if name == "Candle" {
            return preview + """
            -- A calm amber flame with gentle flicker and occasional soft dips.
            function loop()
              local t = luxio_millis() / 1000
              local sin, floor, max = math.sin, math.floor, math.max
              local flame = 0.82 + 0.07 * sin(t * 3.1) + 0.05 * sin(t * 7.7)
                + 0.03 * sin(t * 13.9) - 0.18 * max(0, sin(t * 0.73)) ^ 16
              for i = 0, luxio_get_pixel_count() - 1 do
                local glow = flame + 0.02 * sin(i * 2.4 + t * 5.3)
                luxio_set_pixel_color(i, floor(255 * glow), floor(155 * glow), floor(48 * glow))
              end
            end
            """
        }
        if name == "Cyberpunk" {
            return preview + """
            -- Cyan and magenta neon bands drifting through deep violet.
            function loop()
              local t = luxio_millis() / 1000
              local count = luxio_get_pixel_count()
              local sin, floor, max = math.sin, math.floor, math.max
              for i = 0, count - 1 do
                local x = i / count
                local cyan = max(0, sin(x * 18.85 - t * 1.8)) ^ 6
                local pink = max(0, sin(x * 12.57 + t * 1.3 + 2)) ^ 6
                local shimmer = 0.85 + 0.15 * sin(t * 8 + i * 1.7)
                luxio_set_pixel_color(i, floor((12 + 243 * pink) * shimmer), floor(220 * cyan * shimmer), floor(math.min(255, 35 + 130 * pink + 220 * cyan) * shimmer))
              end
            end
            """
        }
        if name == "Rainbow" || name == "Colorloop" {
            return preview + """
            -- @parameter Speed,Slider,50,0,100
            -- @parameter Period,Number,20,1,120
            -- @parameter Reverse,Checkbox,false
            function setup() end
            function loop()
              local count = luxio_get_pixel_count()
              local time = luxio_millis() / (luxio_get_parameter("Period") * 1000) * luxio_get_parameter("Speed") / 50
              if luxio_get_parameter("Reverse") then time = -time end
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
        return preview + """
        -- @parameter Speed,Slider,50,0,100
        -- @parameter Spacing,Number,8,1,64
        -- @parameter Pulse,Checkbox,true
        function setup() end
        function loop()
          local phase = luxio_millis() / 1800 * luxio_get_parameter("Speed") / 50
          local pulse = luxio_get_parameter("Pulse")
          local spacing = luxio_get_parameter("Spacing")
          local sin, floor = math.sin, math.floor
          for i = 0, luxio_get_pixel_count() - 1 do
            local t = pulse and (0.35 + 0.65 * (sin(i / spacing + phase) + 1) / 2) or 1
            luxio_set_pixel_color(i, floor(\(rgb[0]) * t), floor(\(rgb[1]) * t), floor(\(rgb[2]) * t))
          end
        end
        """
    }
}
