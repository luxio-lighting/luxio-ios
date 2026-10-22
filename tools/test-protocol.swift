import Foundation

@main struct CodecTest {
    static func main() throws {
        var request = Proto(); request.uint(1, 123); request.uint(2, 1)
        var color = Proto(); color.uint(1, 255); color.uint(5, 17); color.uint(6, 129)
        request.data(3, color.bytes)
        print(request.bytes.base64EncodedString())
        let decoded = try Proto.decode(Data(base64Encoded: CommandLine.arguments[1])!)
        let state = try LightState(decoded.message(3))
        precondition(decoded.number(1) == 123)
        precondition(state.name == "Desk 💡" && state.count == 60 && state.brightness == 0)
        precondition(state.mode == 1)
        precondition(state.channels == [255, 0, 0, 0, 17, 129])
        do { _ = try Proto.decode(Data([0x1a, 0xff])); fatalError("Malformed length accepted") }
        catch { /* Expected: truncated varint must be rejected. */ }
        print("PASS: Swift decoded the TypeScript fixture and rejected malformed input")
    }
}
