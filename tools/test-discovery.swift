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
        var bluetoothCalls = 0
        let nearby = Discovery()
        nearby.foundBluetooth(address: "ble://first", name: "Nearby Luxio") { bytes, _ in
            bluetoothCalls += 1
            let request = try Proto.decode(bytes)
            var config = Proto(); config.string(1, "Paired Luxio"); config.string(2, "WS2805"); config.uint(3, 60)
            var state = Proto(); state.string(1, "bluetooth-fingerprint"); state.uint(2, 24); state.data(3, config.bytes)
            var response = Proto(); response.uint(1, UInt64(request.number(1))); response.data(3, state.bytes)
            return response.bytes
        }
        nearby.foundBluetooth(address: "ble://second", name: "Nearby Luxio") { _, _ in
            bluetoothCalls += 1
            throw LuxioError.message("Pairing was cancelled")
        }
        precondition(nearby.lights.count == 2, "Same-name advertisements must stay distinct until their identities are known")
        precondition(nearby.clients["ble://first"]?.state == nil && bluetoothCalls == 0, "Advertising must not request state or pair")
        let cloudBeforeNearby = DiscoveryProtocol.cloudCalls
        await nearby.start()
        precondition(DiscoveryProtocol.cloudCalls == cloudBeforeNearby + 1, "Unconnected Bluetooth advertisements must not suppress cloud discovery")
        await nearby.refresh()
        await nearby.refresh(includeCloud: true)
        precondition(bluetoothCalls == 0, "Startup, polling and manual refresh must never connect to unselected Bluetooth devices")
        let first = nearby.lights.first { $0.id == "ble://first" }!
        let connected = try! await nearby.connectBluetooth(first)
        precondition(bluetoothCalls == 1 && connected.id == "bluetooth-fingerprint" && connected.name == "Paired Luxio")
        precondition(nearby.clients[connected.id]?.usingBluetooth == true)
        precondition(!nearby.lights.contains { $0.id == first.id } && nearby.clients[first.id] == nil)
        let pairedClient = nearby.clients[connected.id]!
        nearby.foundBluetooth(address: "ble://first", name: "Short name") { bytes, _ in
            bluetoothCalls += 1
            let request = try Proto.decode(bytes)
            var state = Proto(); state.string(1, "bluetooth-fingerprint")
            var response = Proto(); response.uint(1, UInt64(request.number(1))); response.data(3, state.bytes)
            return response.bytes
        }
        precondition(bluetoothCalls == 1 && nearby.clients[connected.id] === pairedClient, "Repeated advertisements must reuse the verified client without connecting")
        precondition(nearby.lights.filter { $0.id == connected.id }.count == 1 && !nearby.lights.contains { $0.id == first.id })
        let second = nearby.lights.first { $0.id == "ble://second" }!
        do { _ = try await nearby.connectBluetooth(second); preconditionFailure("Failed pairing was accepted") } catch {}
        let afterFailure = bluetoothCalls
        await nearby.refresh()
        precondition(bluetoothCalls == afterFailure + 1, "Only the already-connected first device may be polled after failed pairing")
        precondition(nearby.clients[second.id]?.state == nil && nearby.lights.contains { $0.id == second.id }, "Cancelled pairing must leave a tappable device for explicit retry")
        nearby.foundBluetooth(address: "ble://expired", name: "Gone Luxio", seenAt: Date(timeIntervalSinceNow: -30)) { _, _ in
            preconditionFailure("Expired advertisements must not connect")
        }
        await nearby.refresh()
        precondition(!nearby.lights.contains { $0.id == "ble://expired" } && nearby.clients["ble://expired"] == nil)
        let lanClient = fallback.clients["online"]!
        precondition(lanClient.bluetoothRequest == nil)
        fallback.foundBluetooth(address: "ble://same-lan-device", name: "Different advertised name") { bytes, _ in
            let request = try Proto.decode(bytes)
            var state = Proto(); state.string(1, "online")
            var response = Proto(); response.uint(1, UInt64(request.number(1))); response.data(3, state.bytes)
            return response.bytes
        }
        precondition(lanClient.bluetoothRequest == nil, "Advertisement alone must not enable automatic Bluetooth fallback")
        let duplicate = fallback.lights.first { $0.id == "ble://same-lan-device" }!
        let merged = try! await fallback.connectBluetooth(duplicate)
        precondition(merged.id == "online" && fallback.lights.count == 1 && fallback.clients["online"] === lanClient)
        precondition(lanClient.bluetoothRequest != nil, "A user-selected Bluetooth connection must merge with its verified Wi-Fi device")
        let invalid = Discovery()
        invalid.foundBluetooth(address: "ble://invalid", name: "Invalid Luxio") { bytes, _ in
            let request = try Proto.decode(bytes)
            var response = Proto(); response.uint(1, UInt64(request.number(1))); response.data(3, Data())
            return response.bytes
        }
        do { _ = try await invalid.connectBluetooth(invalid.lights[0]); preconditionFailure("Missing identity was accepted") } catch {}
        precondition(invalid.clients["ble://invalid"]?.state == nil)
        print("PASS: mDNS/cloud discovery, advertisement-only Bluetooth cards, explicit connection, failure/retry, expiry, identity merging and refresh minimum")
    }
}
