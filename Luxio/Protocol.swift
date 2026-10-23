import Foundation
import Combine

// Minimal proto3 wire codec for luxio.proto. Unknown fields are skipped so newer
// firmware remains readable. Field numbers match packages/protocol/luxio.proto.
struct Proto {
    var bytes = Data()
    mutating func uint(_ field: Int, _ value: UInt64) {
        for var n in [UInt64(field << 3), value] {
            while n > 127 { bytes.append(UInt8(n & 127) | 128); n >>= 7 }
            bytes.append(UInt8(n))
        }
    }
    mutating func data(_ field: Int, _ value: Data) {
        for var n in [UInt64(field << 3 | 2), UInt64(value.count)] {
            while n > 127 { bytes.append(UInt8(n & 127) | 128); n >>= 7 }
            bytes.append(UInt8(n))
        }
        bytes.append(value)
    }
    mutating func real(_ field: Int, _ value: Double) {
        var tag = UInt64(field << 3 | 1)
        while tag > 127 { bytes.append(UInt8(tag & 127) | 128); tag >>= 7 }
        bytes.append(UInt8(tag))
        var bits = value.bitPattern.littleEndian
        bytes.append(Data(bytes: &bits, count: 8))
    }
    mutating func string(_ field: Int, _ value: String) { data(field, Data(value.utf8)) }
    static func decode(_ data: Data) throws -> [Int: [Data]] {
        let bytes = [UInt8](data); var index = 0; var fields: [Int: [Data]] = [:]
        func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for shift in stride(from: 0, through: 63, by: 7) {
                guard index < bytes.count else { throw LuxioError.message("Truncated Protobuf message") }
                let byte = bytes[index]; index += 1
                if shift == 63 && byte > 1 { throw LuxioError.message("Invalid Protobuf integer") }
                value |= UInt64(byte & 127) << shift
                if byte & 128 == 0 { return value }
            }
            throw LuxioError.message("Invalid Protobuf integer")
        }
        while index < bytes.count {
            let tag = try varint(); let field = Int(tag >> 3)
            guard field > 0 else { throw LuxioError.message("Invalid Protobuf field") }
            switch tag & 7 {
            case 0:
                let value = try varint()
                var little = value.littleEndian
                fields[field, default: []].append(Data(bytes: &little, count: 8))
            case 2:
                let size = try varint()
                guard size <= 32768, size <= bytes.count - index else { throw LuxioError.message("Invalid Protobuf size") }
                fields[field, default: []].append(Data(bytes[index..<index + Int(size)])); index += Int(size)
            case 1: guard index + 8 <= bytes.count else { throw LuxioError.message("Truncated field") }; fields[field, default: []].append(Data(bytes[index..<index + 8])); index += 8
            case 5: guard index + 4 <= bytes.count else { throw LuxioError.message("Truncated field") }; index += 4
            default: throw LuxioError.message("Unsupported Protobuf wire type")
            }
        }
        return fields
    }
}
extension Dictionary where Key == Int, Value == [Data] {
    func text(_ field: Int) -> String { String(data: self[field]?.first ?? Data(), encoding: .utf8) ?? "" }
    func number(_ field: Int) -> Int { (self[field]?.first ?? Data()).enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) } }
    func real(_ field: Int) -> Double {
        let bits = (self[field]?.first ?? Data()).enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }
        return Double(bitPattern: bits)
    }
    func message(_ field: Int) throws -> [Int: [Data]] { try Proto.decode(self[field]?.first ?? Data()) }
}
enum LuxioError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
struct Light: Identifiable, Decodable {
    let deviceId: String
    var name: String
    let lan_ip: String
    var id: String { deviceId }
}
struct AnimationParameter: Identifiable, Equatable {
    var name: String, boolean: Bool, value: Double, defaultValue: Double, minimum: Double, maximum: Double
    var numberInput: Bool
    var id: String { name }
    init(_ fields: [Int: [Data]]) {
        name = fields.text(1); boolean = fields.number(2) != 0; value = fields.real(3)
        defaultValue = fields.real(4); minimum = fields.real(5); maximum = fields.real(6); numberInput = fields.number(7) != 0
    }
    var proto: Proto {
        var result = Proto(); result.string(1, name); result.uint(2, boolean ? 1 : 0); result.real(3, value); result.uint(7, numberInput ? 1 : 0); return result
    }
}
struct LightState {
    var deviceId = ""
    var animationRevision = 0
    var animationPreview: [[Int]] = []
    var parameters: [AnimationParameter] = []
    var on = false
    var build = 0
    var lanIP = ""
    var mode: Int?
    var supportsGradients: Bool { count > 1 }
    var supportsWhiteTemperature: Bool { strip == "WS2805" }
    var supportsWhite: Bool { strip == "WS2814" }
    var activeGradient = "", activeColor = "", scriptName = ""
    var gradient: [Int: [Data]]?
    var name = "Luxio", strip = "WS2805", activeScript = ""
    var count = 60, gpio = 16, channel = 0, brightness = 180
    var channels = [Int](repeating: 0, count: 6)
    var previewChannels: [[Int]] {
        if mode == 1, let gradient {
            let colors = (gradient[3] ?? []).compactMap { try? Proto.decode($0) }.map { color in (1...6).map { color.number($0) } }
            if !colors.isEmpty { return colors }
        }
        if mode == 2 { return animationPreview }
        return [channels]
    }
    init(_ fields: [Int: [Data]]) throws {
        deviceId = fields.text(1)
        animationPreview = try (fields[15] ?? []).map { data in
            let color = try Proto.decode(data); return (1...6).map { color.number($0) }
        }
        parameters = try (fields[14] ?? []).map { AnimationParameter(try Proto.decode($0)) }
        animationRevision = fields.number(16)
        build = fields.number(2); lanIP = fields.text(7)
        let config = try fields.message(3); name = config.text(1); strip = config.text(2)
        count = config.number(3); gpio = config.number(4); channel = config.number(5)
        on = build >= 11 ? fields.number(9) != 0 : fields.number(4) > 0
        brightness = min(256, max(1, fields.number(4)))
        if build < 11 { brightness = fields.number(4) > 0 ? Int((Double(fields.number(4)) * 256 / 255).rounded()) : 16 }
        activeScript = fields.text(6); activeGradient = fields.text(10); activeColor = fields.text(12); scriptName = fields.text(13)
        gradient = fields[11] == nil ? nil : try fields.message(11)
        mode = fields.number(2) >= 5 || fields[8] != nil ? fields.number(8) : nil
        let color = try fields.message(5); channels = (1...6).map { color.number($0) }
    }
}
@MainActor final class LightClient: ObservableObject {
    @Published var state: LightState?
    @Published var error: String?
    @Published var lastBrightness = 16
    @Published var libraryRevision = 0
    let address: String
    private var nextId: UInt64 = 1
    private var lastAppliedId: UInt64 = 0
    init(address: String) { self.address = address }
    func request(_ operation: Int, payload: Proto = Proto()) async throws -> [Int: [Data]] {
        try Task.checkCancellation()
        if [17, 20, 21, 23].contains(operation), state?.supportsGradients != true {
            throw LuxioError.message("Gradients require more than one LED/controller")
        }
        if [1, 17, 20, 21, 27, 28].contains(operation), let state {
            let fields = try Proto.decode(payload.bytes)
            let colors: [Data]
            if operation == 1 { colors = fields[3] ?? [] }
            else if [27, 28].contains(operation) { colors = try fields.message(14)[3] ?? [] }
            else { colors = try fields.message(11)[3] ?? [] }
            for bytes in colors {
                let color = try Proto.decode(bytes)
                if (!state.supportsWhite && color.number(4) != 0) || (!state.supportsWhiteTemperature && (color.number(5) != 0 || color.number(6) != 0)) {
                    throw LuxioError.message("White channels are unavailable on this strip type")
                }
            }
        }
        var message = Proto(); let id = nextId; nextId += 1
        message.uint(1, id); message.uint(2, UInt64(operation)); message.bytes.append(payload.bytes)
        let host = address.contains("://") ? address : "http://\(address)"
        guard let url = URL(string: host + "/api") else { throw LuxioError.message("Invalid device address") }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 10
        request.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type"); request.httpBody = message.bytes
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 32768 else { throw LuxioError.message("Device returned an invalid response") }
        var fields = try Proto.decode(data)
        guard fields.number(1) == id else { throw LuxioError.message("Mismatched response") }
        if !fields.text(2).isEmpty { throw LuxioError.message(fields.text(2)) }
        if fields[3] != nil && id >= lastAppliedId {
            let updated = try LightState(fields.message(3))
            state = updated; lastAppliedId = id
            lastBrightness = updated.brightness
        }
        if [5, 18, 25].contains(operation) {
            let listField = operation == 5 ? 4 : operation == 18 ? 15 : 18
            let nextField = operation == 5 ? 11 : operation == 18 ? 17 : 20
            let offsetField = operation == 5 ? 9 : operation == 18 ? 13 : 16
            let next = fields.number(nextField)
            if next > 0 {
                let offset = try Proto.decode(payload.bytes).number(offsetField)
                guard next > offset, !(fields[listField] ?? []).isEmpty else { throw LuxioError.message("Invalid library listing continuation") }
                var continuation = Proto(); continuation.uint(offsetField, UInt64(next))
                let page = try await self.request(operation, payload: continuation)
                fields[listField, default: []].append(contentsOf: page[listField] ?? [])
                fields.removeValue(forKey: nextField)
            }
        }
        return fields
    }
    func refresh() async {
        do { _ = try await request(0); error = nil }
        catch {
            // SwiftUI cancels refresh and polling tasks as views change.
            if !Task.isCancelled && !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                self.error = error.localizedDescription
            }
        }
    }
    func color(_ channels: [Int]) async {
        var color = Proto(); for (i, value) in channels.enumerated() { color.uint(i + 1, UInt64(value)) }
        var payload = Proto(); payload.data(3, color.bytes)
        do { _ = try await request(1, payload: payload); error = nil } catch { self.error = error.localizedDescription }
    }
    func power(_ on: Bool) async {
        var payload = Proto()
        let modern = (state?.build ?? 11) >= 11
        if modern { payload.uint(10, on ? 1 : 0) }
        else { payload.uint(4, on ? UInt64(max(1, Int((Double(lastBrightness) * 255 / 256).rounded()))) : 0) }
        do { _ = try await request(modern ? 15 : 2, payload: payload); error = nil } catch { self.error = error.localizedDescription }
    }
    func brightness(_ level: Int) async {
        guard (1...256).contains(level) else { error = "Brightness must be 1–256"; return }
        var payload = Proto(); payload.uint(4, UInt64((state?.build ?? 11) >= 11 ? level : max(1, Int((Double(level) * 255 / 256).rounded()))))
        do { _ = try await request(2, payload: payload); error = nil } catch { self.error = error.localizedDescription }
    }
}
