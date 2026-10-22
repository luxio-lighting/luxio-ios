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
            let offset = input.number(9); Self.offsets.append(offset)
            var response = Proto(); response.uint(1, UInt64(input.number(1)))
            for i in offset..<min(offset + 64, 150) {
                var script = Proto(); script.string(1, "id-\(i)"); script.string(2, "Saved \(i)"); script.uint(4, 1)
                response.data(4, script.bytes)
            }
            response.uint(11, UInt64(Self.broken ? 64 : (offset + 64 < 150 ? offset + 64 : 0)))
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.bytes); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
@main struct ScriptPagesTest {
    @MainActor static func main() async throws {
        URLProtocol.registerClass(PageProtocol.self)
        defer { URLProtocol.unregisterClass(PageProtocol.self) }
        let client = LightClient(address: "luxio-pagination.test")
        let response = try await client.request(5)
        precondition(PageProtocol.offsets == [0, 64, 128])
        precondition(response[4]?.count == 150)
        let last = try Proto.decode(response[4]!.last!)
        precondition(last.text(2) == "Saved 149")
        PageProtocol.broken = true
        do { _ = try await client.request(5); preconditionFailure("Expected invalid continuation") }
        catch { precondition(error.localizedDescription == "Invalid script listing continuation") }
        print("PASS: native iOS fetches all script pages and rejects non-progressing cursors")
    }
}
