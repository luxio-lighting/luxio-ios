import SwiftUI

// Each visible preview owns a VM. Lua executes on this actor, never the UI thread.
actor AnimationPreviewEngine {
    private var runtime: OpaquePointer?
    private var count = 0
    deinit { luxio_animation_destroy(runtime) }

    func start(source: String, count: Int, strip: String, parameters: [AnimationParameter]) -> Bool {
        luxio_animation_destroy(runtime)
        runtime = luxio_animation_create(Int32(count), Int32(strip.dropFirst(2)) ?? 0)
        self.count = count
        guard let runtime else { return false }
        for parameter in parameters {
            guard luxio_animation_parameter(runtime, parameter.name, parameter.boolean, parameter.value) else { return false }
        }
        return luxio_animation_start(runtime, source)
    }
    func frame(milliseconds: UInt32, parameters: [AnimationParameter]) -> [[Int]]? {
        guard let runtime else { return nil }
        for parameter in parameters { _ = luxio_animation_parameter(runtime, parameter.name, parameter.boolean, parameter.value) }
        guard let pixels = luxio_animation_frame(runtime, milliseconds) else { return nil }
        // Bound drawing cost while running Lua against the real controller count.
        let samples = min(count, 65)
        return (0..<samples).map { sample in
            let index = samples == 1 ? 0 : sample * (count - 1) / (samples - 1)
            return (0..<6).map { Int(pixels[index * 6 + $0]) }
        }
    }
}

struct LiveLightBackdrop: View {
    @ObservedObject var client: LightClient
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var pixels: [[Int]] = []
    @State private var renderedKey = ""

    var body: some View {
        let state = client.state
        let key = visible && scenePhase == .active && !reduceMotion && state?.on == true && state?.mode == 2
            ? "\(state?.animationRevision ?? 0)-\(state?.activeScript ?? "")-\(state?.scriptName ?? "")-\(state?.count ?? 0)-\(state?.strip ?? "")" : ""
        let live = !key.isEmpty && renderedKey == key && !pixels.isEmpty
        ZStack {
            LightBackdrop(channels: [])
            LightBackdrop(channels: live ? pixels : state?.previewChannels ?? [], duration: live ? 0 : 0.4)
                // Live frames update without interpolation; power fades outside that transaction.
                .opacity(state?.on == true ? 1 : 0)
                .animation(.smooth(duration: 0.35), value: state?.on)
        }
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .task(id: key) {
                pixels = []; renderedKey = ""
                guard !key.isEmpty, let initial = state else { return }
                let engine = AnimationPreviewEngine()
                do {
                    let source: String
                    let parameters: [AnimationParameter]
                    if initial.build >= 20 {
                        // Empty ID reads the active source, including unsaved Studio animations.
                        let reply = try await client.request(6)
                        let snapshot = try LightState(reply.message(3))
                        guard snapshot.animationRevision == initial.animationRevision else { return }
                        let animation = try reply.message(5)
                        source = animation.text(3); parameters = snapshot.parameters
                    } else if let preset = LightPreset.all.first(where: { !($0.isGradient) && "Luxio · \($0.name)" == initial.scriptName }) {
                        source = preset.source; parameters = initial.parameters
                    } else if !initial.activeScript.isEmpty {
                        var payload = Proto(); payload.string(8, initial.activeScript)
                        let reply = try await client.request(6, payload: payload)
                        source = try reply.message(5).text(3); parameters = initial.parameters
                    } else { return }
                    guard !Task.isCancelled, await engine.start(source: source, count: initial.count, strip: initial.strip, parameters: parameters) else { return }
                    let start = ContinuousClock.now
                    while !Task.isCancelled {
                        let elapsed = start.duration(to: .now)
                        let milliseconds = UInt32(truncatingIfNeeded: elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
                        guard let frame = await engine.frame(milliseconds: milliseconds, parameters: client.state?.parameters ?? parameters), !Task.isCancelled else { break }
                        pixels = frame; renderedKey = key
                        try await Task.sleep(for: .milliseconds(33))
                    }
                } catch { /* A preview failure must never prevent controlling the light. */ }
                if renderedKey == key { pixels = []; renderedKey = "" }
            }
    }
}
