import Foundation

final class RefreshProtocol: URLProtocol {
    static var animationError = ""
    static var failure: Error? = URLError(.cancelled)
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "luxio-refresh.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let error = Self.failure { client?.urlProtocol(self, didFailWithError: error); return }
        do {
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            let input = try Proto.decode(body)
            var response = Proto(); response.uint(1, UInt64(input.number(1)))
            var state = Proto(); state.uint(2, 35); response.data(3, state.bytes)
            response.string(22, Self.animationError)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.bytes)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main struct RefreshTests {
    @MainActor static func main() async {
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
        URLProtocol.registerClass(RefreshProtocol.self)
        defer { URLProtocol.unregisterClass(RefreshProtocol.self) }
        let client = LightClient(address: "luxio-refresh.test")
        for failure: Error in [URLError(.cancelled)] {
            RefreshProtocol.failure = failure
            client.error = nil
            await client.refresh()
            precondition(client.error == nil, "Cancellation must not appear as a device error: \(failure) → \(client.error ?? "nil")")
            client.error = "Existing error"
            await client.refresh()
            precondition(client.error == "Existing error", "Cancellation must not replace an existing error")
        }
        RefreshProtocol.failure = URLError(.timedOut)
        client.error = nil
        await client.refresh()
        precondition(client.error == URLError(.timedOut).localizedDescription, "Real network errors must still be visible")
        precondition(client.failure == nil, "Background polling must never create a toast")
        await client.refresh(userInitiated: true)
        precondition(client.failure?.title == "luxio-refresh.test · Refresh")
        let refreshFailure = client.failure?.id
        await client.power(true)
        precondition(client.failure?.title == "luxio-refresh.test · Change power" && client.failure?.id != refreshFailure)
        let firstFailure = client.failure?.id
        await client.power(true)
        precondition(client.failure?.id != firstFailure, "Repeating an action must create a fresh toast")
        client.failure = nil
        RefreshProtocol.failure = URLError(.cancelled)
        await client.power(false)
        await client.color([255, 0, 0, 0, 0, 0])
        await client.brightness(16)
        await client.refresh(userInitiated: true)
        precondition(client.failure == nil, "Cancelled actions must stay silent")
        RefreshProtocol.failure = URLError(.timedOut)
        for previous in [nil, client.error] {
            client.error = previous
            let refresh = Task { await client.refresh() }
            refresh.cancel()
            await refresh.value
            precondition(client.error == previous, "Cancelled SwiftUI tasks must not replace the current error")
        }
        RefreshProtocol.failure = nil
        await client.refresh()
        precondition(client.error == nil, "Successful refresh must clear the previous error")
        RefreshProtocol.animationError = "Animation exceeded its instruction limit"
        await client.refresh()
        precondition(client.error == nil && client.animationError == RefreshProtocol.animationError, "Runtime errors must survive successful state refreshes")
        await client.refresh()
        precondition(client.animationError == RefreshProtocol.animationError, "Polling must not hide an animation failure")
        RefreshProtocol.animationError = ""
        await client.refresh()
        precondition(client.animationError == nil, "A cleared firmware error must disappear")
        print("PASS: refresh ignores task and URL cancellation, keeps background errors silent, reports action failures, and clears errors on success")
    }
}
