import Foundation

@main struct PreviewTest {
    static func main() throws {
        var red = Proto(); red.uint(1, 255)
        var green = Proto(); green.uint(2, 255)
        var blue = Proto(); blue.uint(3, 255)
        var state = Proto(); state.uint(2, 19); state.uint(8, 0); state.data(5, red.bytes)
        let solidState = try LightState(Proto.decode(state.bytes))
        precondition(solidState.previewChannels == [[255, 0, 0, 0, 0, 0]])
        var gradient = Proto(); gradient.data(3, green.bytes); gradient.data(3, blue.bytes)
        state = Proto(); state.uint(2, 19); state.uint(8, 1); state.data(5, red.bytes); state.data(11, gradient.bytes)
        let gradientState = try LightState(Proto.decode(state.bytes))
        precondition(gradientState.previewChannels == [[0, 255, 0, 0, 0, 0], [0, 0, 255, 0, 0, 0]])
        state = Proto(); state.uint(2, 19); state.uint(8, 2); state.data(5, red.bytes); state.data(15, blue.bytes); state.data(15, green.bytes)
        let animationState = try LightState(Proto.decode(state.bytes))
        precondition(animationState.previewChannels == [[0, 0, 255, 0, 0, 0], [0, 255, 0, 0, 0, 0]])
        state = Proto(); state.uint(2, 19); state.uint(8, 2); state.data(5, red.bytes)
        let noPreview = try LightState(Proto.decode(state.bytes))
        precondition(noPreview.previewChannels.isEmpty, "An animation without a hint must not show a stale solid color")
        var slider = Proto(); slider.string(1, "Speed"); slider.real(3, 50); slider.real(5, 0); slider.real(6, 100)
        var number = Proto(); number.string(1, "Spacing"); number.real(3, 8); number.real(5, 1); number.real(6, 64); number.uint(7, 1)
        var checkbox = Proto(); checkbox.string(1, "Pulse"); checkbox.uint(2, 1); checkbox.real(3, 1)
        state = Proto(); state.uint(2, 21); state.data(14, slider.bytes); state.data(14, number.bytes); state.data(14, checkbox.bytes)
        let parameters = try LightState(Proto.decode(state.bytes)).parameters
        precondition(parameters.count == 3 && !parameters[0].numberInput && parameters[1].numberInput && parameters[2].boolean)
        let patch = try Proto.decode(parameters[1].proto.bytes)
        precondition(patch.number(7) == 1 && patch.real(3) == 8)
        print("PASS: solid, gradient, animation and missing-preview palettes")
    }
}
