import Foundation

final class BluetoothHTTPProtocol: URLProtocol {
    static var requests = 0
    static var failure: Error = URLError(.cannotConnectToHost)
    static var response: Data?
    override class func canInit(with request: URLRequest) -> Bool { ["bluetooth.test", "192.0.2.10"].contains(request.url?.host ?? "") }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        if let response = Self.response {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response)
            client?.urlProtocolDidFinishLoading(self)
        } else { client?.urlProtocol(self, didFailWithError: Self.failure) }
    }
    override func stopLoading() {}
}

@main struct BluetoothTests {
    @MainActor static func main() async throws {
        for size in [1, 20, 247, 1024, 32768] {
            let payload = Data((0..<size).map { UInt8($0 % 251) })
            let packet = try BluetoothFrame.encode(payload)
            for fragment in [1, 3, 7, 20, 244, 512] {
                var frame = BluetoothFrame(), result: Data?
                for offset in stride(from: 0, to: packet.count, by: fragment) {
                    result = try frame.append(packet.subdata(in: offset..<min(offset + fragment, packet.count)))
                    if offset + fragment < packet.count { precondition(result == nil) }
                }
                precondition(result == payload)
                let second = try frame.append(packet); precondition(second == payload)
            }
        }
        for malformed in [Data("BAD!\0\0\0\u{1}".utf8), Data("LXP1\0\0\0\0".utf8), Data([76, 88, 80, 49, 0, 0, 128, 1]), Data([76, 88, 80, 49, 0, 0, 0, 1, 1, 2])] {
            var frame = BluetoothFrame()
            do { _ = try frame.append(malformed); preconditionFailure("Malformed frame accepted") } catch {}
        }
        do { _ = try BluetoothFrame.encode(Data(repeating: 1, count: 32769)); preconditionFailure("Oversized request accepted") } catch {}
        var network = Proto(); network.string(1, "Test Wi-Fi"); network.uint(2, 131); network.uint(3, 1)
        let wifi = WifiNetwork(try Proto.decode(network.bytes)); precondition(wifi.rssi == -66 && wifi.passwordRequired && wifi.ssid == "Test Wi-Fi")

        URLProtocol.registerClass(BluetoothHTTPProtocol.self)
        defer { URLProtocol.unregisterClass(BluetoothHTTPProtocol.self) }
        var bleCalls = 0
        let exchange: (Data, TimeInterval) async throws -> Data = { bytes, _ in
            bleCalls += 1
            let request = try Proto.decode(bytes)
            var state = Proto(); state.string(1, "fingerprint"); state.uint(2, 24)
            var response = Proto(); response.uint(1, UInt64(request.number(1))); response.data(3, state.bytes)
            if request.number(2) == 0 {
                var status = Proto(); status.uint(1, 1); status.string(11, "Test Wi-Fi"); status.string(12, "192.0.2.1")
                status.string(13, "192.0.2.1"); status.string(13, "1.1.1.1")
                response.data(21, status.bytes)
            }
            if request.number(2) == 12 { response.string(6, "12345678901"); response.string(7, "MT:test") }
            return response.bytes
        }
        let nearby = LightClient(address: "ble://test"); nearby.bluetoothRequest = exchange
        _ = try await nearby.request(0)
        precondition(nearby.state?.deviceId == "fingerprint" && nearby.usingBluetooth)
        precondition(nearby.wifiStatus?.connected == true && nearby.wifiStatus?.ssid == "Test Wi-Fi")
        precondition(nearby.wifiStatus?.gateway == "192.0.2.1" && nearby.wifiStatus?.dns == ["192.0.2.1", "1.1.1.1"])
        let pairing = try await nearby.request(12); precondition(pairing.text(7) == "MT:test")
        precondition(nearby.wifiStatus?.ssid == "Test Wi-Fi", "Non-status responses must preserve Wi-Fi details")
        var credentials = Proto(); credentials.string(1, "Test Wi-Fi"); credentials.string(2, "password")
        var payload = Proto(); payload.data(6, credentials.bytes)
        _ = try await nearby.request(4, payload: payload)
        precondition(BluetoothHTTPProtocol.requests == 0 && bleCalls == 3)

        let legacy = LightClient(address: "ble://legacy")
        legacy.wifiStatus = nearby.wifiStatus
        legacy.bluetoothRequest = { bytes, _ in
            let request = try Proto.decode(bytes)
            var state = Proto(); state.string(1, "legacy"); state.uint(2, 23)
            var response = Proto(); response.uint(1, UInt64(request.number(1))); response.data(3, state.bytes)
            return response.bytes
        }
        _ = try await legacy.request(0)
        precondition(legacy.wifiStatus == nil, "Legacy firmware must not retain stale Wi-Fi details")
        let disconnected = WifiStatus([:])
        precondition(!disconnected.connected && disconnected.ssid.isEmpty && disconnected.gateway.isEmpty && disconnected.dns.isEmpty)

        let fallback = LightClient(address: "bluetooth.test"); fallback.bluetoothRequest = exchange
        _ = try await fallback.request(0)
        precondition(BluetoothHTTPProtocol.requests == 1 && bleCalls == 4 && fallback.usingBluetooth)
        _ = try await fallback.request(12)
        precondition(BluetoothHTTPProtocol.requests == 1 && bleCalls == 5)

        let mutation = LightClient(address: "bluetooth.test"); mutation.bluetoothRequest = exchange
        do { _ = try await mutation.request(7); preconditionFailure("An ambiguous mutation was replayed") } catch {}
        precondition(bleCalls == 5 && mutation.usingBluetooth)
        _ = try await mutation.request(0); precondition(bleCalls == 6)

        BluetoothHTTPProtocol.failure = URLError(.cancelled)
        let cancelled = LightClient(address: "bluetooth.test"); cancelled.bluetoothRequest = exchange
        do { _ = try await cancelled.request(0); preconditionFailure("Cancellation ignored") } catch {}
        precondition(bleCalls == 6 && !cancelled.usingBluetooth)
        var recoveredState = Proto(); recoveredState.string(1, "lan-fingerprint")
        var recovered = Proto(); recovered.uint(1, 1); recovered.data(3, recoveredState.bytes)
        BluetoothHTTPProtocol.response = recovered.bytes
        let lanRecovery = LightClient(address: "bluetooth.test"); lanRecovery.usingBluetooth = true
        lanRecovery.nextNetworkCheck = ContinuousClock.now.advanced(by: .seconds(60))
        lanRecovery.bluetoothRequest = { _, _ in throw URLError(.networkConnectionLost) }
        _ = try await lanRecovery.request(0)
        precondition(!lanRecovery.usingBluetooth && lanRecovery.state?.deviceId == "lan-fingerprint")
        let beforeMutation = BluetoothHTTPProtocol.requests
        let bleMutation = LightClient(address: "bluetooth.test"); bleMutation.usingBluetooth = true
        bleMutation.bluetoothRequest = { _, _ in throw URLError(.networkConnectionLost) }
        do { _ = try await bleMutation.request(7); preconditionFailure("BLE mutation replayed on LAN") } catch {}
        precondition(!bleMutation.usingBluetooth && BluetoothHTTPProtocol.requests == beforeMutation)
        let bleCancelled = LightClient(address: "bluetooth.test"); bleCancelled.usingBluetooth = true
        bleCancelled.nextNetworkCheck = ContinuousClock.now.advanced(by: .seconds(60))
        bleCancelled.bluetoothRequest = { _, _ in throw URLError(.cancelled) }
        do { _ = try await bleCancelled.request(0); preconditionFailure("BLE cancellation ignored") } catch {}
        precondition(bleCancelled.usingBluetooth && BluetoothHTTPProtocol.requests == beforeMutation)
        let mismatched = LightClient(address: "ble://bad")
        mismatched.bluetoothRequest = { _, _ in var response = Proto(); response.uint(1, 99); return response.bytes }
        do { _ = try await mismatched.request(0); preconditionFailure("Mismatched response accepted") } catch {}

        // A healthy BLE connection must yield to Wi-Fi once its retry is due.
        var preferredState = Proto(); preferredState.string(1, "fingerprint"); preferredState.string(7, "192.0.2.10")
        var preferredReply = Proto(); preferredReply.uint(1, 3); preferredReply.data(3, preferredState.bytes)
        BluetoothHTTPProtocol.response = preferredReply.bytes
        fallback.nextNetworkCheck = ContinuousClock.now
        let beforePreference = bleCalls
        _ = try await fallback.request(0)
        precondition(!fallback.usingBluetooth && bleCalls == beforePreference)
        preferredReply = Proto(); preferredReply.uint(1, 4); preferredReply.data(3, preferredState.bytes)
        BluetoothHTTPProtocol.response = preferredReply.bytes
        _ = try await fallback.request(2)
        precondition(!fallback.usingBluetooth && bleCalls == beforePreference)

        let advertised = LightClient(address: "ble://advertised")
        advertised.bluetoothRequest = { bytes, _ in
            bleCalls += 1
            let request = try Proto.decode(bytes)
            var response = Proto(); response.uint(1, UInt64(request.number(1))); response.data(3, preferredState.bytes)
            return response.bytes
        }
        _ = try await advertised.request(0)
        precondition(advertised.usingBluetooth)
        preferredReply = Proto(); preferredReply.uint(1, 2); preferredReply.data(3, preferredState.bytes)
        BluetoothHTTPProtocol.response = preferredReply.bytes
        let beforeAdvertised = bleCalls
        _ = try await advertised.request(0)
        precondition(!advertised.usingBluetooth && bleCalls == beforeAdvertised)

        // Reject a stale IP answering for another light, then stay on BLE
        // between probes instead of delaying every state refresh/control.
        var stranger = Proto(); stranger.string(1, "another-light")
        preferredReply = Proto(); preferredReply.uint(1, 3); preferredReply.data(3, stranger.bytes)
        BluetoothHTTPProtocol.response = preferredReply.bytes
        _ = try await advertised.request(0)
        precondition(advertised.usingBluetooth && advertised.state?.deviceId == "fingerprint")
        let afterRejection = BluetoothHTTPProtocol.requests
        _ = try await advertised.request(0)
        _ = try await advertised.request(2)
        precondition(advertised.usingBluetooth && BluetoothHTTPProtocol.requests == afterRejection)
        print("PASS: BLE framing/limits, setup/pairing, Wi-Fi preference/recovery, advertised IP verification, probe throttling, cancellation and no mutation replay")
    }
}
