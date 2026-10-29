import Foundation

final class NoNetworkProtocol: URLProtocol {
    static var calls = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.calls += 1; client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

@main struct SimulatorTests {
    @MainActor static func main() async throws {
        URLProtocol.registerClass(NoNetworkProtocol.self)
        let previous = UserDefaults.standard.data(forKey: "luxio.simulator.snapshot")
        let enabled = UserDefaults.standard.object(forKey: "luxio.simulator.enabled")
        let count = UserDefaults.standard.object(forKey: "lastDiscoveredLightCount")
        UserDefaults.standard.removeObject(forKey: "luxio.simulator.snapshot")
        defer {
            UserDefaults.standard.set(previous, forKey: "luxio.simulator.snapshot")
            UserDefaults.standard.set(enabled, forKey: "luxio.simulator.enabled")
            UserDefaults.standard.set(count, forKey: "lastDiscoveredLightCount")
            URLProtocol.unregisterClass(NoNetworkProtocol.self)
        }
        let discovery = Discovery()
        let light = await discovery.addSimulator()
        let client = discovery.clients[light.id]!
        precondition(client.isSimulator && client.state!.count == 60 && client.state!.supportsWhiteTemperature)
        precondition(client.state!.supportedStripTypes == SimulatorDevice.supportedStripTypes)
        let rgbSimulator = SimulatorDevice()
        for type in ["WS2811", "WS2813", "WS2815"] {
            var config = Proto(); config.string(1, "RGB Test"); config.string(2, type); config.uint(3, 60)
            var payload = Proto(); payload.data(5, config.bytes)
            _ = try rgbSimulator.request(3, payload: payload)
            precondition(!rgbSimulator.state.supportsWhite && !rgbSimulator.state.supportsWhiteTemperature)
            var white = Proto(); white.uint(4, 255); payload = Proto(); payload.data(3, white.bytes)
            do { _ = try rgbSimulator.request(1, payload: payload); fatalError("RGB strip accepted white") }
            catch { /* Expected. */ }
        }
        var dim = Proto(); dim.uint(4, 16); _ = try await client.request(2, payload: dim)
        var off = Proto(); off.uint(10, 0); _ = try await client.request(15, payload: off)
        precondition(client.state!.brightness == 16 && !client.state!.on)
        var white = Proto(); white.uint(5, 200); white.uint(6, 55)
        var payload = Proto(); payload.data(3, white.bytes); _ = try await client.request(1, payload: payload)
        precondition(client.state!.on && client.state!.brightness == 16 && client.state!.channels == [0,0,0,0,200,55])
        var red = Proto(); red.uint(1, 255)
        var blue = Proto(); blue.uint(3, 255)
        var ids: [Int: String] = [:]
        for mode in 0...2 {
            var record = Proto(); record.string(2, "Saved \(mode)")
            if mode == 2 { record.string(3, LightPreset.all[0].source) }
            else { record.data(3, red.bytes); if mode == 1 { record.data(3, blue.bytes); record.string(4, "points-metadata") } }
            var save = Proto(); save.data(mode == 0 ? 14 : mode == 1 ? 11 : 7, record.bytes)
            let response = try await client.request(mode == 0 ? 27 : mode == 1 ? 20 : 7, payload: save)
            let item = try response.message(mode == 0 ? 19 : mode == 1 ? 16 : 5)
            let id = item.text(1); precondition(!id.isEmpty); ids[mode] = id
            _ = try await client.request(15, payload: off)
            var run = Proto(); run.string(mode == 0 ? 15 : mode == 1 ? 12 : 8, id)
            _ = try await client.request(mode == 0 ? 30 : mode == 1 ? 23 : 10, payload: run)
            precondition(client.state!.on && client.state!.mode == mode && client.state!.brightness == 16)
            if mode == 1 { precondition(client.state!.gradient!.text(4) == "points-metadata") }
            let fresh = LightClient(address: "simulator")
            precondition(fresh.state!.mode == mode, "Current output must survive relaunch")
            let list = try await fresh.request(mode == 0 ? 25 : mode == 1 ? 18 : 5)
            precondition(list[mode == 0 ? 18 : mode == 1 ? 15 : 4]?.count == 1)
            var renamed = Proto(); renamed.string(1, id); renamed.string(2, "Renamed \(mode)")
            for field in mode == 2 ? [3] : mode == 1 ? [3,4] : [3] { for data in item[field] ?? [] { renamed.data(field, data) } }
            var update = Proto(); update.data(mode == 0 ? 14 : mode == 1 ? 11 : 7, renamed.bytes)
            _ = try await client.request(mode == 0 ? 28 : mode == 1 ? 21 : 8, payload: update)
            let fetched = try await client.request(mode == 0 ? 26 : mode == 1 ? 19 : 6, payload: run)
            let fetchedItem = try fetched.message(mode == 0 ? 19 : mode == 1 ? 16 : 5)
            precondition(fetchedItem.text(2) == "Renamed \(mode)")
        }
        for preset in LightPreset.all where !preset.isGradient {
            var script = Proto(); script.string(2, preset.name); script.string(3, preset.source)
            var play = Proto(); play.data(7, script.bytes); _ = try await client.request(31, payload: play)
            precondition(client.state!.animationPreview.map { Array($0.prefix(3)) } == preset.previewColors)
            let active = try await client.request(6)
            let activeItem = try active.message(5)
            precondition(activeItem.text(3) == preset.source)
            if var parameter = client.state!.parameters.first {
                let revision = client.state!.animationRevision
                parameter.value = parameter.minimum
                var patch = Proto(); patch.data(17, parameter.proto.bytes)
                _ = try await client.request(32, payload: patch)
                precondition(client.state!.parameters.first!.value == parameter.minimum && client.state!.animationRevision == revision)
                let fresh = LightClient(address: "simulator")
                precondition(fresh.state!.parameters.first!.value == parameter.minimum)
            }
        }
        for mode in 0...2 {
            var remove = Proto(); remove.string(mode == 0 ? 15 : mode == 1 ? 12 : 8, ids[mode]!)
            _ = try await client.request(mode == 0 ? 29 : mode == 1 ? 22 : 9, payload: remove)
            let list = try await client.request(mode == 0 ? 25 : mode == 1 ? 18 : 5)
            precondition(list[mode == 0 ? 18 : mode == 1 ? 15 : 4] == nil)
        }
        for strip in ["SK6812", "WS2814", "WS2812", "WS2805"] {
            var config = Proto(); config.string(1, "Strip test"); config.string(2, strip); config.uint(3, 1024)
            var settings = Proto(); settings.data(5, config.bytes)
            _ = try await client.request(3, payload: settings)
            let fresh = LightClient(address: "simulator")
            precondition(fresh.state!.strip == strip && fresh.state!.count == 1024)
            var color = Proto(); color.uint(strip == "WS2805" ? 5 : strip == "WS2812" ? 1 : 4, 255)
            var request = Proto(); request.data(3, color.bytes)
            _ = try await client.request(1, payload: request)
            precondition(client.state!.channels.contains(255))
            if strip == "SK6812" {
                var invalid = Proto(); invalid.uint(5, 255)
                var request = Proto(); request.data(3, invalid.bytes)
                do { _ = try await client.request(1, payload: request); preconditionFailure("SK6812 must reject warm/cool channels") }
                catch { precondition(error.localizedDescription.contains("Channel unavailable")) }
            }
        }
        await discovery.refresh()
        precondition(discovery.lights.count == 1)
        discovery.removeSimulator(); precondition(discovery.lights.isEmpty)
        precondition(NoNetworkProtocol.calls == 0, "Simulated controls must never use HTTP")
        print("PASS: offline RGBCCT controls, separate brightness/power, all animation presets and parameters, saved libraries, persistence, and removal")
    }
}
