import Foundation
@main struct ExportPresets {
    static func main() throws {
        let output = LightPreset.all.map { preset -> [String: Any] in
            ["name": preset.name, "colors": preset.colors, "previewColors": preset.previewColors, "isGradient": preset.isGradient, "source": preset.source]
        }
        print(String(data: try JSONSerialization.data(withJSONObject: output), encoding: .utf8)!)
    }
}
