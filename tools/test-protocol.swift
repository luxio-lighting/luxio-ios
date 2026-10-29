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
        precondition(state.name == "Desk 💡" && state.count == 60 && state.brightness == 256 && !state.on)
        precondition(state.mode == 1 && state.supportsMatter)
        precondition(state.wifiEnabled && state.matterEnabled, "Absent feature settings default enabled")
        var off = Proto(); off.uint(1, 0)
        var features = Proto(); features.string(1, "Radio test"); features.string(2, "SK6812"); features.uint(3, 1024)
        features.data(7, off.bytes); features.data(8, off.bytes)
        var featureFields = try decoded.message(3); featureFields[3] = [features.bytes]
        let disabled = try LightState(featureFields)
        precondition(!disabled.wifiEnabled && !disabled.matterEnabled && disabled.supportsMatter)
        precondition(disabled.supportsWhite && !disabled.supportsWhiteTemperature)
        var capability = Proto(); capability.uint(17, 1)
        var noMatter = try decoded.message(3); noMatter[17] = try Proto.decode(capability.bytes)[17]
        let noMatterState = try LightState(noMatter)
        precondition(!noMatterState.supportsMatter)
        precondition(!state.relayEnabled && state.relayGPIO == 0 && !state.relayInverted)
        var relay = Proto(); relay.uint(1, 1); relay.uint(2, 12); relay.uint(3, 1)
        var config = try decoded.message(3).message(3); config[6] = [relay.bytes]
        var configBytes = Proto()
        for (field, values) in config { for value in values {
            if [1, 2, 6].contains(field) { configBytes.data(field, value) }
            else { configBytes.uint(field, UInt64(config.number(field))) }
        } }
        var relayFields = try decoded.message(3); relayFields[3] = [configBytes.bytes]
        let withRelay = try LightState(relayFields)
        precondition(withRelay.relayEnabled && withRelay.relayGPIO == 12 && withRelay.relayInverted)
        relay = Proto(); relay.uint(1, 1); relay.uint(2, 0)
        configBytes = Proto(); configBytes.data(6, relay.bytes); relayFields[3] = [configBytes.bytes]
        let gpioZero = try LightState(relayFields)
        precondition(gpioZero.relayEnabled && gpioZero.relayGPIO == 0 && !gpioZero.relayInverted)
        var power = Proto(); power.uint(2, 15); power.uint(10, 1)
        let decodedPower = try Proto.decode(power.bytes)
        precondition(decodedPower.number(10) == 1)
        var extra = Proto(); extra.uint(9, 1)
        // Proto fields may occur more than once; use a fresh state for the on case.
        var onFields = try decoded.message(3); onFields[9] = try Proto.decode(extra.bytes)[9]
        let poweredState = try LightState(onFields)
        precondition(poweredState.on)
        precondition(state.supportedStripTypes == ["WS2811", "WS2813", "WS2815", "FUTURE"])
        precondition(state.channels == [255, 0, 0, 0, 17, 129])
        do { _ = try Proto.decode(Data([0x1a, 0xff])); fatalError("Malformed length accepted") }
        catch { /* Expected: truncated varint must be rejected. */ }
        print("PASS: Swift decoded the TypeScript fixture and rejected malformed input")
    }
}
