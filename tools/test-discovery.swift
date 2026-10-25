import Foundation

final class DiscoveryProtocol: URLProtocol {
    static var online = true
    static var cloudCalls = 0
    static var deviceCalls = 0
    static var cloudFails = false
    override class func canInit(with request: URLRequest) -> Bool {
        ["http", "https"].contains(request.url?.scheme ?? "")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data: Data
            if request.url?.host == "api.luxio.lighting" {
                Self.cloudCalls += 1
                if Self.cloudFails { throw URLError(.cannotConnectToHost) }
                data = Data("[{\"deviceId\":\"online\",\"name\":\"Cloud light\",\"lan_ip\":\"online.test\"},{\"deviceId\":\"offline\",\"name\":\"Offline light\",\"lan_ip\":\"offline.test\"}]".utf8)
            } else {
                Self.deviceCalls += 1
                if request.url?.host != "online.test" || !Self.online { throw URLError(.cannotConnectToHost) }
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
                var config = Proto(); config.string(1, "Local light"); config.string(2, "WS2805"); config.uint(3, 60)
                var state = Proto(); state.string(1, "online"); state.uint(2, 20); state.data(3, config.bytes); state.uint(4, 16)
                var response = Proto(); response.uint(1, UInt64(input.number(1))); response.data(3, state.bytes)
                data = response.bytes
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class AdvertisedLight: NetService {
    override var hostName: String? { "online.test" }
    override func txtRecordData() -> Data? { NetService.data(fromTXTRecord: ["id": Data("online".utf8)]) }
}

@main struct DiscoveryTests {
    @MainActor static func main() async {
        let preferences = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        UserDefaults.standard.setVolatileDomain(["luxio.simulator.enabled": false], forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(preferences, forName: UserDefaults.argumentDomain) }
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
        URLProtocol.registerClass(DiscoveryProtocol.self)
        defer { URLProtocol.unregisterClass(DiscoveryProtocol.self) }
        let discovery = Discovery()
        let startup = Task { await discovery.start() }
        let service = AdvertisedLight(domain: "local.", type: "_luxio._tcp.", name: "Advertised light", port: 80)
        discovery.netServiceDidResolveAddress(service)
        for _ in 0..<100 {
            if !discovery.lights.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        await startup.value
        precondition(discovery.lights.count == 1, "mDNS resolution must verify and show a reachable light")
        precondition(discovery.clients["online"]?.state?.name == "Local light", "Discovery must cache device state")
        precondition(DiscoveryProtocol.cloudCalls == 0)
        let cached = discovery.clients["online"]!
        let beforeManual = ContinuousClock.now
        await discovery.refresh(includeCloud: true)
        precondition(beforeManual.duration(to: .now) >= .milliseconds(500), "Manual refresh must last at least 500 ms")
        precondition(DiscoveryProtocol.cloudCalls == 1)
        precondition(discovery.lights.count == 1, "Offline cloud candidates must not be shown")
        precondition(discovery.clients["online"] === cached, "Refresh must reuse the cached client")
        DiscoveryProtocol.online = false
        await discovery.refresh()
        precondition(discovery.lights.isEmpty, "Unreachable devices must disappear")
        precondition(DiscoveryProtocol.cloudCalls == 1, "Background polling must stay local")
        DiscoveryProtocol.online = true
        await discovery.refresh()
        precondition(discovery.lights.count == 1, "Recovered local devices must reappear without a cloud query")
        precondition(discovery.clients["online"] === cached)
        DiscoveryProtocol.cloudFails = true
        let beforeFailure = ContinuousClock.now
        await discovery.refresh(includeCloud: true)
        precondition(beforeFailure.duration(to: .now) >= .milliseconds(500))
        precondition(discovery.lights.count == 1, "Cloud failure must not hide reachable local devices")
        precondition(discovery.error != nil)
        DiscoveryProtocol.cloudFails = false
        let callsBeforeFallback = DiscoveryProtocol.cloudCalls
        let fallback = Discovery()
        await fallback.start()
        precondition(DiscoveryProtocol.cloudCalls == callsBeforeFallback + 1, "Empty mDNS discovery must query the cloud once")
        precondition(fallback.lights.count == 1 && fallback.lights.first?.id == "online", "Only reachable cloud results should appear")
        await fallback.refresh()
        precondition(DiscoveryProtocol.cloudCalls == callsBeforeFallback + 1, "Background checks must not repeatedly query the cloud")
        print("PASS: mDNS preference, cloud fallback, cached clients, offline filtering/recovery, and 500 ms refresh minimum")
    }
}
