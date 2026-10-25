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
#if os(iOS)
    private let bluetooth = BluetoothDiscovery()
    private var bluetoothChecks = Set<String>()
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
            if !Task.isCancelled { UserDefaults.standard.set(lights.count, forKey: "lastDiscoveredLightCount") }
        }
        if UserDefaults.standard.bool(forKey: "luxio.simulator.enabled") { _ = await addSimulator() }
#if DEBUG
        if let address = ProcessInfo.processInfo.environment["LUXIO_UI_TEST_ADDRESS"] {
            await add(Light(deviceId: "ui-fixture", name: "Library test", lan_ip: address))
            return
        }
#endif
#if os(iOS)
        bluetooth.status = { [weak self] in self?.bluetoothStatus = $0 }
        bluetooth.found = { [weak self] connection in
            guard let self, self.bluetoothChecks.insert(connection.address).inserted else { return }
            Task {
                defer { self.bluetoothChecks.remove(connection.address) }
                let client = LightClient(address: connection.address)
                client.bluetoothRequest = { [weak connection] bytes, timeout in
                    guard let connection else { throw LuxioError.message("Luxio is no longer nearby") }
                    return try await connection.request(bytes, timeout: timeout)
                }
                do {
                    _ = try await client.request(0)
                    guard let state = client.state, !state.deviceId.isEmpty else { return }
                    let id = state.deviceId
                    self.bluetoothStatus = nil
                    if let existing = self.clients[id] {
                        existing.bluetoothRequest = client.bluetoothRequest
                        if !self.lights.contains(where: { $0.id == id }), let candidate = self.candidates[id] { _ = await self.check(candidate) }
                    } else {
                        let light = Light(deviceId: id, name: state.name, lan_ip: connection.address)
                        self.candidates[id] = light; self.clients[id] = client; self.lights.append(light)
                    }
                } catch {
                    if !Task.isCancelled && !(error is CancellationError) { self.bluetoothStatus = error.localizedDescription }
                }
            }
        }
        bluetooth.start()
#endif
        browser.searchForServices(ofType: "_luxio._tcp.", inDomain: "local.")
        // Give Bonjour a short discovery window before showing the empty state.
        try? await Task.sleep(for: .seconds(2))
        await refresh()
        if lights.allSatisfy({ $0.id == "luxio-simulator" }) && !Task.isCancelled { await refresh(includeCloud: true) }
    }

    func addSimulator() async -> Light {
        UserDefaults.standard.set(true, forKey: "luxio.simulator.enabled")
        let light = Light(deviceId: "luxio-simulator", name: "Luxio Simulator", lan_ip: "simulator")
        await add(light)
        return lights.first(where: { $0.id == light.id }) ?? light
    }

    func removeSimulator() {
        UserDefaults.standard.set(false, forKey: "luxio.simulator.enabled")
        candidates.removeValue(forKey: "luxio-simulator"); clients.removeValue(forKey: "luxio-simulator")
        lights.removeAll { $0.id == "luxio-simulator" }
        UserDefaults.standard.set(lights.count, forKey: "lastDiscoveredLightCount")
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
        if !Task.isCancelled && !loading { UserDefaults.standard.set(lights.count, forKey: "lastDiscoveredLightCount") }
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
