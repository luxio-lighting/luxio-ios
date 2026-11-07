import Foundation
import Combine

@MainActor final class Discovery: NSObject, ObservableObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    @Published private(set) var lights: [Light] = []
    @Published var error: String?
    @Published private(set) var searching = false
    @Published private(set) var loading = true
    let previousCount = max(0, UserDefaults.standard.integer(forKey: "lastDiscoveredLightCount"))
    private(set) var clients: [String: LightClient] = [:]
    private var candidates: [String: Light] = [:]
    private var checks: [String: UInt64] = [:]
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    private var started = false
    @Published var bluetoothStatus: String?
    private var bluetoothChecks = Set<String>()
    private var bluetoothIdentities: [String: String] = [:]
    private var bluetoothLastSeen: [String: Date] = [:]
#if os(iOS)
    private let bluetooth = BluetoothDiscovery()
    func setBluetoothActive(_ active: Bool) {
#if DEBUG
        if ProcessInfo.processInfo.environment["LUXIO_UI_TEST_ADDRESS"] != nil { return }
#endif
        if active { bluetooth.start() } else { bluetooth.stop() }
    }
#endif
    override init() { super.init(); browser.delegate = self }

    func start() async {
        guard !started else { return }; started = true
        defer {
            loading = false
            if !Task.isCancelled { UserDefaults.standard.set(lights.filter { $0.id != "luxio-simulator" }.count, forKey: "lastDiscoveredLightCount") }
        }
        UserDefaults.standard.removeObject(forKey: "luxio.simulator.enabled")
        UserDefaults.standard.removeObject(forKey: "luxio.simulator.snapshot")
#if DEBUG
        if let address = ProcessInfo.processInfo.environment["LUXIO_UI_TEST_ADDRESS"] {
            if let name = ProcessInfo.processInfo.environment["LUXIO_UI_TEST_BLUETOOTH_NAME"] {
                foundBluetooth(address: "ble://ui-fixture", name: name) { bytes, timeout in
                    var request = URLRequest(url: URL(string: "http://\(address)/api")!)
                    request.httpMethod = "POST"; request.httpBody = bytes; request.timeoutInterval = timeout
                    request.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LuxioError.message("Couldn't connect to Luxio over Bluetooth. Tap the device to try again.") }
                    return data
                }
            } else {
                await add(Light(deviceId: "ui-fixture", name: "Library test", lan_ip: address))
            }
            return
        }
#endif
#if os(iOS)
        bluetooth.status = { [weak self] in self?.bluetoothStatus = $0 }
        bluetooth.found = { [weak self] connection, name in
            self?.foundBluetooth(address: connection.address, name: name) { [weak connection] bytes, timeout in
                guard let connection else { throw LuxioError.message("Luxio is no longer nearby") }
                return try await connection.request(bytes, timeout: timeout)
            }
        }
        bluetooth.start()
#endif
        browser.searchForServices(ofType: "_luxio._tcp.", inDomain: "local.")
        // Give Bonjour a short discovery window before showing the empty state.
        try? await Task.sleep(for: .seconds(2))
        await refresh()
        if !lights.contains(where: { $0.id != "luxio-simulator" && clients[$0.id]?.state != nil }) && !Task.isCancelled { await refresh(includeCloud: true) }
    }

    func foundBluetooth(address: String, name: String, seenAt: Date = .now, request: @escaping (Data, TimeInterval) async throws -> Data) {
        if let id = bluetoothIdentities[address], let client = clients[id] {
            client.bluetoothRequest = request
            return
        }
        bluetoothLastSeen[address] = seenAt
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let light = Light(deviceId: address, name: name.isEmpty ? "Luxio" : name, lan_ip: address)
        let client = clients[address] ?? LightClient(address: address)
        client.bluetoothRequest = request
        clients[address] = client
        if let index = lights.firstIndex(where: { $0.id == address }) {
            if lights[index].name != light.name { lights[index] = light }
        } else { lights.append(light) }
        // Advertisements never enter candidates: periodic refresh must not initiate pairing.
    }

    func connectBluetooth(_ light: Light) async throws -> Light {
        guard let client = clients[light.id], client.state == nil, light.lan_ip.hasPrefix("ble://"),
              bluetoothChecks.insert(light.id).inserted else { throw LuxioError.message("Luxio is already connecting or is no longer nearby.") }
        defer { bluetoothChecks.remove(light.id) }
        do {
            let response = try await client.request(0, timeout: 60)
            try Task.checkCancellation()
            guard response[3] != nil, let state = client.state, !state.deviceId.isEmpty, state.deviceId != light.id else { throw LuxioError.message("Luxio returned an invalid device identity.") }
            let id = state.deviceId
            // Merge by the verified device identity, never by the advertised name.
            let verified: Light
            if let existing = clients[id], let candidate = candidates[id] {
                existing.bluetoothRequest = client.bluetoothRequest
                if let current = lights.first(where: { $0.id == id }) {
                    verified = current
                } else {
                    client.address = candidate.lan_ip
                    clients[id] = client
                    verified = Light(deviceId: id, name: state.name, lan_ip: candidate.lan_ip)
                    lights.append(verified)
                }
            } else {
                verified = Light(deviceId: id, name: state.name, lan_ip: light.lan_ip)
                clients[id] = client; candidates[id] = verified
                if let index = lights.firstIndex(where: { $0.id == id }) { lights[index] = verified }
                else { lights.append(verified) }
            }
            bluetoothIdentities[light.lan_ip] = id
            bluetoothLastSeen.removeValue(forKey: light.lan_ip)
            lights.removeAll { $0.id == light.id }
            clients.removeValue(forKey: light.id)
            bluetoothStatus = nil
            return verified
        } catch {
            client.state = nil
            throw error
        }
    }

    func addSimulator() async -> Light {
        let light = Light(deviceId: "luxio-simulator", name: "Luxio Simulator", lan_ip: "simulator")
        await add(light)
        return lights.first(where: { $0.id == light.id }) ?? light
    }

    func removeSimulator() {
        candidates.removeValue(forKey: "luxio-simulator"); clients.removeValue(forKey: "luxio-simulator")
        lights.removeAll { $0.id == "luxio-simulator" }
        UserDefaults.standard.set(lights.filter { $0.id != "luxio-simulator" }.count, forKey: "lastDiscoveredLightCount")
    }

    func add(_ light: Light) async {
        // Prefer a previously discovered identity when manually entering its address.
        let candidate = candidates.values.first(where: { $0.lan_ip == light.lan_ip }) ?? light
        candidates[candidate.id] = candidate
        _ = await check(candidate)
    }

    @discardableResult func check(_ light: Light) async -> Bool {
        guard candidates[light.id]?.lan_ip == light.lan_ip else { return false }
        let client: LightClient
        if let existing = clients[light.id] {
            client = existing
            if client.address != light.lan_ip { client.address = light.lan_ip; client.usingBluetooth = false }
        } else { client = LightClient(address: light.lan_ip); clients[light.id] = client }
        let revision = (checks[light.id] ?? 0) + 1; checks[light.id] = revision
        do {
            let response = try await client.request(0, timeout: 3)
            guard response[3] != nil, let state = client.state else { throw LuxioError.message("Device returned no state") }
            guard checks[light.id] == revision, candidates[light.id]?.lan_ip == light.lan_ip else { return false }
            let verified = Light(deviceId: light.id, name: state.name, lan_ip: light.lan_ip)
            client.error = nil
            if let index = lights.firstIndex(where: { $0.id == light.id }) { lights[index] = verified }
            else { lights.append(verified) }
            return true
        } catch {
            if !Task.isCancelled && !(error is CancellationError) && (error as? URLError)?.code != .cancelled,
               checks[light.id] == revision, candidates[light.id]?.lan_ip == light.lan_ip {
                lights.removeAll { $0.id == light.id }
            }
            return false
        }
    }

    func refresh(includeCloud: Bool = false) async {
        let minimum = ContinuousClock.now.advanced(by: .milliseconds(500))
        for (address, seenAt) in bluetoothLastSeen where Date().timeIntervalSince(seenAt) > 20 && !bluetoothChecks.contains(address) {
            lights.removeAll { $0.id == address }
            clients.removeValue(forKey: address)
            bluetoothLastSeen.removeValue(forKey: address)
        }
        if includeCloud {
#if os(iOS)
            setBluetoothActive(true)
#endif
            searching = true; error = nil
            var useCloud = true
#if DEBUG
            useCloud = ProcessInfo.processInfo.environment["LUXIO_UI_TEST_ADDRESS"] == nil
#endif
            if useCloud {
                do {
                    var request = URLRequest(url: URL(string: "https://api.luxio.lighting/devices")!); request.timeoutInterval = 7
                    let (data, response) = try await URLSession.shared.data(for: request)
                    try Task.checkCancellation()
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LuxioError.message("Cloud discovery is unavailable. Local discovery is still running.") }
                    for light in try JSONDecoder().decode([Light].self, from: data) where candidates[light.id] == nil || !lights.contains(where: { $0.id == light.id }) {
                        candidates[light.id] = light
                    }
                } catch {
                    if !Task.isCancelled && !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                        self.error = error.localizedDescription
                    }
                }
            }
        }
        // Keep known local addresses so a light reappears when it comes back online.
        await withTaskGroup(of: Void.self) { group in
            for light in candidates.values {
                group.addTask { _ = await self.check(light) }
            }
        }
        if !Task.isCancelled && !loading { UserDefaults.standard.set(lights.filter { $0.id != "luxio-simulator" }.count, forKey: "lastDiscoveredLightCount") }
        if includeCloud {
            try? await Task.sleep(until: minimum, clock: .continuous)
            searching = false
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard !services.contains(where: { $0 == service }) else { return }
        services.append(service); service.delegate = self; service.resolve(withTimeout: 5)
    }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName else { return }
        let txt = sender.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        let id = txt["id"].flatMap { String(data: $0, encoding: .utf8) } ?? host
        let light = Light(deviceId: id, name: sender.name, lan_ip: "\(host):\(sender.port)")
        Task { await add(light) }
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 == service }
        service.stop()
        // Verify disappearance over HTTP; a transient multicast loss is not proof of an outage.
        Task { await refresh() }
    }
}
