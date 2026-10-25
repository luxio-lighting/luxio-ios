import Foundation

// Local device API: the normal app controls and Lua previews use this without HTTP.
final class SimulatorDevice {
    var state = LightState()
    private var libraries: [Int: [Data]] = [0: [], 1: [], 2: []]
    private var animation: Data?

    init(saved: Data? = nil) {
        state.deviceId = "luxio-simulator"; state.name = "Luxio Simulator"
        state.build = 21; state.lanIP = "simulator"; state.mode = 0; state.on = true
        state.channels = [0, 210, 255, 0, 0, 0]
        if let saved, let fields = try? Proto.decode(saved), let restored = try? LightState(fields.message(3)),
           restored.deviceId == state.deviceId, ["WS2805", "WS2814", "WS2812", "SK6812"].contains(restored.strip), (1...1024).contains(restored.count) {
            state = restored
            libraries = [0: fields[18] ?? [], 1: fields[15] ?? [], 2: fields[4] ?? []]
            animation = fields[5]?.first
        }
    }

    var snapshot: Proto {
        var config = Proto(); config.string(1, state.name); config.string(2, state.strip)
        config.uint(3, UInt64(state.count)); config.uint(4, UInt64(state.gpio)); config.uint(5, UInt64(state.channel))
        var current = Proto(); current.string(1, state.deviceId); current.uint(2, UInt64(state.build)); current.data(3, config.bytes)
        current.uint(4, UInt64(state.brightness)); current.string(6, state.activeScript); current.string(7, state.lanIP)
        current.uint(8, UInt64(state.mode ?? 0)); current.uint(9, state.on ? 1 : 0)
        current.string(10, state.activeGradient); current.string(12, state.activeColor); current.string(13, state.scriptName)
        current.uint(16, UInt64(state.animationRevision))
        var color = Proto(); for (index, value) in state.channels.enumerated() { color.uint(index + 1, UInt64(value)) }; current.data(5, color.bytes)
        if let fields = state.gradient {
            var gradient = Proto(); gradient.string(1, fields.text(1)); gradient.string(2, fields.text(2))
            for color in fields[3] ?? [] { gradient.data(3, color) }; gradient.string(4, fields.text(4))
            current.data(11, gradient.bytes)
        }
        for parameter in state.parameters {
            var value = parameter.proto; value.real(4, parameter.defaultValue); value.real(5, parameter.minimum); value.real(6, parameter.maximum)
            current.data(14, value.bytes)
        }
        for channels in state.animationPreview {
            var color = Proto(); for (index, value) in channels.enumerated() { color.uint(index + 1, UInt64(value)) }; current.data(15, color.bytes)
        }
        var result = Proto(); result.data(3, current.bytes)
        if let animation { result.data(5, animation) }
        for color in libraries[0] ?? [] { result.data(18, color) }
        for gradient in libraries[1] ?? [] { result.data(15, gradient) }
        for animation in libraries[2] ?? [] { result.data(4, animation) }
        return result
    }

    func request(_ operation: Int, payload: Proto) throws -> [Int: [Data]] {
        let input = try Proto.decode(payload.bytes)
        var response = Proto()
        switch operation {
        case 0: break
        case 1:
            let fields = try input.message(3)
            let channels = (1...6).map { fields.number($0) }
            guard channels.allSatisfy({ (0...255).contains($0) }), (state.supportsWhiteTemperature || (channels[4] == 0 && channels[5] == 0)), (state.supportsWhite || channels[3] == 0) else { throw LuxioError.message("Channel unavailable on this strip type") }
            state.channels = channels; state.on = true; state.mode = 0
            state.activeColor = ""; state.activeGradient = ""; state.activeScript = ""; state.scriptName = ""
            state.gradient = nil; state.parameters = []; state.animationPreview = []; animation = nil
        case 2:
            guard (1...256).contains(input.number(4)) else { throw LuxioError.message("Brightness must be 1–256") }
            state.brightness = input.number(4)
        case 15: state.on = input.number(10) != 0
        case 3:
            let config = try input.message(5); let name = config.text(1).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.utf8.count <= 63, ["WS2805", "WS2814", "WS2812", "SK6812"].contains(config.text(2)), (1...1024).contains(config.number(3)) else { throw LuxioError.message("Invalid simulator settings") }
            if state.strip != config.text(2) || state.count != config.number(3) {
                state.channels = [Int](repeating: 0, count: 6); state.mode = 0
                state.activeColor = ""; state.activeGradient = ""; state.activeScript = ""; state.scriptName = ""
                state.gradient = nil; state.parameters = []; state.animationPreview = []; animation = nil
            }
            state.name = name; state.count = config.number(3); state.strip = config.text(2)
            if state.count == 1 && state.mode == 1 { state.mode = 0; state.gradient = nil; state.activeGradient = "" }
        case 5, 18, 25:
            let mode = operation == 25 ? 0 : operation == 18 ? 1 : 2
            for item in libraries[mode] ?? [] { response.data(mode == 0 ? 18 : mode == 1 ? 15 : 4, item) }
        case 6, 19, 26:
            let mode = operation == 26 ? 0 : operation == 19 ? 1 : 2
            let id = input.text(mode == 0 ? 15 : mode == 1 ? 12 : 8)
            let item = mode == 2 && id.isEmpty ? animation : (libraries[mode] ?? []).first { (try? Proto.decode($0).text(1)) == id }
            guard let item else { throw LuxioError.message("Saved item not found") }
            response.data(mode == 0 ? 19 : mode == 1 ? 16 : 5, item)
        case 9, 22, 29:
            let mode = operation == 29 ? 0 : operation == 22 ? 1 : 2
            let id = input.text(mode == 0 ? 15 : mode == 1 ? 12 : 8)
            libraries[mode]?.removeAll { (try? Proto.decode($0).text(1)) == id }
            if state.activeColor == id { state.activeColor = "" }
            if state.activeGradient == id { state.activeGradient = "" }
            if state.activeScript == id { state.activeScript = "" }
        case 7, 8, 10, 17, 20, 21, 23, 27, 28, 30, 31:
            let mode = [27, 28, 30].contains(operation) ? 0 : [17, 20, 21, 23].contains(operation) ? 1 : 2
            let create = [7, 20, 27].contains(operation), update = [8, 21, 28].contains(operation)
            let run = [10, 23, 30].contains(operation)
            let id = input.text(mode == 0 ? 15 : mode == 1 ? 12 : 8)
            let bytes = run ? (libraries[mode] ?? []).first { (try? Proto.decode($0).text(1)) == id } : input[mode == 0 ? 14 : mode == 1 ? 11 : 7]?.first
            guard let bytes else { throw LuxioError.message("Saved item not found") }
            let item = try Proto.decode(bytes)
            let itemID = create ? UUID().uuidString.lowercased() : update || run ? item.text(1) : ""
            let name = item.text(2).trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.utf8.count <= 63, !(create || update) || !name.isEmpty else { throw LuxioError.message("A name is required") }
            if update && !(libraries[mode] ?? []).contains(where: { (try? Proto.decode($0).text(1)) == itemID }) { throw LuxioError.message("Saved item not found") }
            var record = Proto(); record.string(1, itemID); record.string(2, name)
            if mode < 2 {
                let colors = item[3] ?? []
                guard mode == 0 ? colors.count == 1 : (2...8).contains(colors.count) && state.count > 1 else { throw LuxioError.message("Invalid number of gradient points") }
                for color in colors {
                    let fields = try Proto.decode(color)
                    guard (1...6).allSatisfy({ (0...255).contains(fields.number($0)) }), (state.supportsWhiteTemperature || (fields.number(5) == 0 && fields.number(6) == 0)), (state.supportsWhite || fields.number(4) == 0) else { throw LuxioError.message("Channel unavailable on this strip type") }
                    record.data(3, color)
                }
                if mode == 1 {
                    guard item.text(4).utf8.count <= 2048 else { throw LuxioError.message("Gradient metadata is too large") }
                    record.string(4, item.text(4))
                }
            } else {
                let source = item.text(3)
                guard !source.isEmpty, source.utf8.count <= 16384 else { throw LuxioError.message("Animation source must be 1–16384 bytes") }
                record.string(3, source); record.uint(4, 2)
                var names = Set<String>(); var header = true; var hasPreview = false
                for raw in source.components(separatedBy: .newlines) {
                    let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if line.hasPrefix("-- @parameter ") {
                        guard header else { throw LuxioError.message("Parameters must be at the top of the animation") }
                        let parts = line.dropFirst(14).components(separatedBy: "//")[0].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        guard parts.count >= 3, parts[0].range(of: "^[A-Za-z][A-Za-z0-9_ ]{0,31}$", options: .regularExpression) != nil, names.insert(parts[0]).inserted, names.count <= 16 else { throw LuxioError.message("Invalid animation parameter") }
                        let boolean = ["Checkbox", "Boolean"].contains(parts[1])
                        let initial: Double, minimum: Double, maximum: Double
                        if boolean {
                            guard parts.count == 3, ["true", "false"].contains(parts[2]) else { throw LuxioError.message("Invalid checkbox parameter") }
                            initial = parts[2] == "true" ? 1 : 0; minimum = 0; maximum = 1
                        } else {
                            guard parts.count == 5, ["Slider", "Number"].contains(parts[1]), let value = Double(parts[2]), let low = Double(parts[3]), let high = Double(parts[4]),
                                  [value, low, high].allSatisfy({ $0.isFinite && abs($0) <= 1e9 }), low < high, value >= low, value <= high else { throw LuxioError.message("Invalid numeric parameter") }
                            initial = value; minimum = low; maximum = high
                        }
                        var value = initial
                        for bytes in item[5] ?? [] {
                            let supplied = AnimationParameter(try Proto.decode(bytes))
                            if supplied.name == parts[0] {
                                guard supplied.boolean == boolean, supplied.value.isFinite, supplied.value >= minimum, supplied.value <= maximum, !boolean || supplied.value == 0 || supplied.value == 1 else { throw LuxioError.message("Invalid parameter value") }
                                value = supplied.value
                            }
                        }
                        var parameter = Proto(); parameter.string(1, parts[0]); parameter.uint(2, boolean ? 1 : 0)
                        parameter.real(3, value); parameter.real(4, initial); parameter.real(5, minimum); parameter.real(6, maximum); parameter.uint(7, parts[1] == "Number" ? 1 : 0)
                        record.data(5, parameter.bytes)
                    } else if line.hasPrefix("-- @preview ") {
                        guard header && !hasPreview else { throw LuxioError.message("Invalid animation preview") }; hasPreview = true
                        let colors = line.dropFirst(12).components(separatedBy: "//")[0].components(separatedBy: ",")
                        guard (2...8).contains(colors.count) else { throw LuxioError.message("Preview requires 2–8 colors") }
                        for value in colors {
                            let hex = value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
                            guard hex.count == 6, let rgb = UInt32(hex, radix: 16) else { throw LuxioError.message("Invalid preview color") }
                            var color = Proto(); color.uint(1, UInt64(rgb >> 16)); color.uint(2, UInt64(rgb >> 8 & 255)); color.uint(3, UInt64(rgb & 255)); record.data(6, color.bytes)
                        }
                    } else if !line.isEmpty && (!line.hasPrefix("--") || line.hasPrefix("--[")) { header = false }
                }
            }
            if create { libraries[mode, default: []].append(record.bytes) }
            else if update, let index = libraries[mode]?.firstIndex(where: { (try? Proto.decode($0).text(1)) == itemID }) { libraries[mode]?[index] = record.bytes }
            else {
                state.mode = mode; state.on = true; state.activeColor = ""; state.activeGradient = ""; state.activeScript = ""; state.scriptName = ""
                state.gradient = nil; state.parameters = []; state.animationPreview = []; animation = nil
                let fields = try Proto.decode(record.bytes)
                if mode == 0 { let color = try fields.message(3); state.channels = (1...6).map { color.number($0) }; state.activeColor = itemID }
                else if mode == 1 { state.gradient = fields; state.activeGradient = itemID }
                else {
                    animation = record.bytes; state.activeScript = itemID; state.scriptName = name; state.animationRevision += 1
                    state.parameters = try (fields[5] ?? []).map { AnimationParameter(try Proto.decode($0)) }
                    state.animationPreview = try (fields[6] ?? []).map { let color = try Proto.decode($0); return (1...6).map { color.number($0) } }
                }
            }
            response.data(mode == 0 ? 19 : mode == 1 ? 16 : 5, record.bytes)
        case 32:
            let requestedName = try input.message(7).text(2)
            guard state.mode == 2, input.text(8).isEmpty || input.text(8) == state.activeScript,
                  input[7] == nil || requestedName == state.scriptName else { throw LuxioError.message("Animation changed") }
            var parameters = state.parameters; var names = Set<String>()
            for bytes in input[17] ?? [] {
                let patch = AnimationParameter(try Proto.decode(bytes))
                guard names.insert(patch.name).inserted, let index = parameters.firstIndex(where: { $0.name == patch.name }), parameters[index].boolean == patch.boolean,
                      patch.value.isFinite, patch.value >= parameters[index].minimum, patch.value <= parameters[index].maximum,
                      !patch.boolean || patch.value == 0 || patch.value == 1 else { throw LuxioError.message("Invalid parameter value") }
                parameters[index].value = patch.value
            }
            state.parameters = parameters
        default: throw LuxioError.message("This feature requires a physical Luxio device")
        }
        let snapshot = try Proto.decode(snapshot.bytes)
        response.data(3, snapshot[3]!.first!)
        return try Proto.decode(response.bytes)
    }
}
