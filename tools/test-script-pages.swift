import Foundation

final class PageProtocol: URLProtocol {
    static var offsets: [Int] = []
    static var broken = false
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "luxio-pagination.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; body.append(contentsOf: buffer.prefix(n)) }
            }
            let input = try Proto.decode(body)
            let op = input.number(2)
            let offsetField = op == 5 ? 9 : op == 18 ? 13 : 16
            let listField = op == 5 ? 4 : op == 18 ? 15 : 18
            let nextField = op == 5 ? 11 : op == 18 ? 17 : 20
            let offset = input.number(offsetField); Self.offsets.append(offset)
            var response = Proto(); response.uint(1, UInt64(input.number(1)))
            for i in offset..<min(offset + 64, 150) {
                var script = Proto(); script.string(1, "id-\(i)"); script.string(2, "Saved \(i)"); script.uint(4, 1)
                response.data(listField, script.bytes)
            }
            response.uint(nextField, UInt64(Self.broken ? 64 : (offset + 64 < 150 ? offset + 64 : 0)))
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.bytes); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
@main struct ScriptPagesTest {
    @MainActor static func main() async throws {
        for value in [-100.25, 0, 0.5, 100, 1e9] {
            var proto = Proto(); proto.real(3, value)
            let decoded = try Proto.decode(proto.bytes); precondition(decoded.real(3) == value)
        }

        URLProtocol.registerClass(PageProtocol.self)
        defer { URLProtocol.unregisterClass(PageProtocol.self) }
        let client = LightClient(address: "luxio-pagination.test")
        for op in [5, 18, 25] {
        PageProtocol.offsets = []; PageProtocol.broken = false
        let field = op == 5 ? 4 : op == 18 ? 15 : 18
        let response = try await client.request(op)
        precondition(PageProtocol.offsets == [0, 64, 128])
        precondition(response[field]?.count == 150)
        let last = try Proto.decode(response[field]!.last!)
        precondition(last.text(2) == "Saved 149")
        PageProtocol.broken = true
        do { _ = try await client.request(op); preconditionFailure("Expected invalid continuation") }
        catch { precondition(error.localizedDescription == "Invalid library listing continuation") }
        }
        for strip in ["WS2812", "WS2814", "WS2805"] {
            for count in [1, 2] {
                var config = Proto(); config.string(2, strip); config.uint(3, UInt64(count))
                var state = Proto(); state.uint(2, 13); state.data(3, config.bytes)
                client.state = try LightState(Proto.decode(state.bytes))
                precondition(client.state!.supportsGradients == (count > 1))
                precondition(client.state!.supportsWhite == (strip == "WS2814"))
                precondition(client.state!.supportsWhiteTemperature == (strip == "WS2805"))
                if count == 1 {
                    do { _ = try await client.request(17); preconditionFailure("Unsupported gradient sent") }
                    catch { precondition(error.localizedDescription.contains("more than one")) }
                }
                for field in [4, 5, 6] where (field == 4 ? strip != "WS2814" : strip != "WS2805") {
                    var color = Proto(); color.uint(field, 255); var payload = Proto(); payload.data(3, color.bytes)
                    do { _ = try await client.request(1, payload: payload); preconditionFailure("Unsupported white channel sent") }
                    catch { precondition(error.localizedDescription.contains("unavailable")) }
                }
            }
        }
        print("PASS: native iOS fetches all color, gradient and animation pages and rejects non-progressing cursors")
    }
}
