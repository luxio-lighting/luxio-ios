import SwiftUI
import Network
import CoreImage.CIFilterBuiltins

private let backdrop = LinearGradient(colors: [Color(red: 0.19, green: 0.105, blue: 0.13), Color(red: 0.095, green: 0.095, blue: 0.11)], startPoint: .top, endPoint: .bottom)
private let tileColor = Color(red: 0.25, green: 0.205, blue: 0.225)
private let accent = Color(red: 0.15, green: 0.48, blue: 1)

extension LightState {
    var usesDarkForeground: Bool {
        let r = Double(channels[0] + channels[3] + channels[4]) + Double(channels[5]) * 0.8
        let g = Double(channels[1] + channels[3]) + Double(channels[4]) * 0.73 + Double(channels[5]) * 0.9
        let b = Double(channels[2] + channels[3]) + Double(channels[4]) * 0.4 + Double(channels[5])
        return (r * 0.2126 + g * 0.7152 + b * 0.0722) / max(r, g, b, 1) > 0.68
    }
    var displayColor: Color {
        let r = Double(channels[0] + channels[3] + channels[4]) + Double(channels[5]) * 0.8
        let g = Double(channels[1] + channels[3]) + Double(channels[4]) * 0.73 + Double(channels[5]) * 0.9
        let b = Double(channels[2] + channels[3]) + Double(channels[4]) * 0.4 + Double(channels[5])
        let peak = max(r, g, b, 1)
        return Color(red: r / peak, green: g / peak, blue: b / peak)
    }
}

@main struct LuxioApp: App {
    var body: some Scene { WindowGroup { LightsView().preferredColorScheme(.dark).tint(accent) } }
}

@MainActor final class Discovery: NSObject, ObservableObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    @Published var lights: [Light] = []
    @Published var error: String?
    @Published var searching = false
    private let browser = NetServiceBrowser()
    private var services: [NetService] = []
    override init() { super.init(); browser.delegate = self }
    func refresh() async {
        searching = true; error = nil
        browser.stop(); services.removeAll()
        browser.searchForServices(ofType: "_luxio._tcp.", inDomain: "local.")
        do {
            var request = URLRequest(url: URL(string: "https://api.luxio.lighting/devices")!); request.timeoutInterval = 7
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw LuxioError.message("Cloud discovery is unavailable. Local discovery is still running.") }
            for light in try JSONDecoder().decode([Light].self, from: data) where !lights.contains(where: { $0.id == light.id }) { lights.append(light) }
        } catch { self.error = error.localizedDescription }
        searching = false
    }
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) { services.append(service); service.delegate = self; service.resolve(withTimeout: 5) }
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName else { return }
        let txt = sender.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        let id = txt["id"].flatMap { String(data: $0, encoding: .utf8) } ?? host
        let light = Light(deviceId: id, name: sender.name, lan_ip: "\(host):\(sender.port)")
        if let index = lights.firstIndex(where: { $0.id == id }) { lights[index] = light } else { lights.append(light) }
    }
}

struct LightsView: View {
    @StateObject private var discovery = Discovery()
    @State private var manual = ""
    @State private var showAdd = false
    var body: some View {
        NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            Text("Home").font(.system(size: 38, weight: .bold)).padding(.bottom, 8)
                            VStack(alignment: .leading, spacing: 12) {
                                Text("LIGHTS").font(.system(size: 11, weight: .semibold)).tracking(1.8).foregroundStyle(.white.opacity(0.65)).padding(.horizontal, 4)
                                if discovery.lights.isEmpty {
                                    VStack(spacing: 16) {
                                        Image(systemName: "light.strip.fill").font(.system(size: 32))
                                        Text(discovery.searching ? "Finding your lights…" : "Your lights live here").font(.headline)
                                        Text("Connect to the same Wi-Fi as your Luxio light, or add its address.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                        Button("Connect a light") { showAdd = true }.buttonStyle(.borderedProminent)
                                    }.frame(maxWidth: .infinity).padding(28).background(tileColor, in: RoundedRectangle(cornerRadius: 16))
                                }
                                ForEach(discovery.lights) { light in LightCard(light: light) }
                            }
                            if discovery.lights.isEmpty, discovery.error != nil {
                                Text("Local discovery is running. Pull down to try again.").font(.footnote).foregroundStyle(.secondary)
                            }
                        }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 24)
                    }.refreshable { await discovery.refresh() }
                    .safeAreaInset(edge: .top, spacing: 0) {
                            HStack {
                                Text("Luxio").font(.system(size: 19, weight: .semibold, design: .rounded))
                                Spacer()
                                Button { showAdd = true } label: { Image(systemName: "plus").font(.system(size: 21, weight: .medium)).frame(width: 44, height: 44).background(.white.opacity(0.12), in: Circle()) }.accessibilityLabel("Connect a light")
                            }.foregroundStyle(.white)
                                .padding(.horizontal, 16).padding(.vertical, 8).background(.ultraThinMaterial)
                    }
                    .background(backdrop.ignoresSafeArea()).toolbar(.hidden, for: .navigationBar)
        }
        .task { await discovery.refresh() }
        .alert("Connect to a light", isPresented: $showAdd) {
            TextField("192.168.1.42", text: $manual).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            Button("Connect") {
                let address = manual.trimmingCharacters(in: .whitespacesAndNewlines)
                if !address.isEmpty && !discovery.lights.contains(where: { $0.lan_ip == address }) { discovery.lights.append(Light(deviceId: address, name: "Luxio", lan_ip: address)) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Enter its local IP address or hostname.") }
    }
}

struct BrightnessSlider: View {
    @Binding var value: Double
    let ink: Color
    var onEditingChanged: (Bool) -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var dragging = false
    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width - 20, 1)
            let progress = min(max(value / 255, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.16)).frame(height: 8)
                Capsule().fill(ink.opacity(0.26)).frame(width: 10 + width * progress, height: 8)
                Circle().fill(.white).frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                    .scaleEffect(dragging ? 1.15 : 1)
                    .offset(x: width * progress)
            }.frame(height: 44).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard enabled else { return }
                        if !dragging { dragging = true; onEditingChanged(true) }
                        value = (min(max((gesture.location.x - 10) / width, 0), 1) * 255).rounded()
                    }
                    .onEnded { _ in
                        guard dragging else { return }
                        dragging = false; onEditingChanged(false)
                    })
        }.frame(height: 44).opacity(enabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.12), value: dragging)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Brightness")
            .accessibilityValue("\(Int(value / 255 * 100)) percent")
            .accessibilityAdjustableAction { direction in
                guard enabled else { return }
                onEditingChanged(true)
                switch direction {
                case .increment: value = min(255, value + 13)
                case .decrement: value = max(0, value - 13)
                @unknown default: break
                }
                onEditingChanged(false)
            }
    }
}

struct LightCard: View {
    let light: Light
    @StateObject private var client: LightClient
    @State private var level = 0.0
    @State private var editing = false
    init(light: Light) { self.light = light; _client = StateObject(wrappedValue: LightClient(address: light.lan_ip)) }
    var body: some View {
        let on = (client.state?.brightness ?? 0) > 0
        let color = client.state?.displayColor ?? tileColor
        let ink: Color = on && client.state?.usesDarkForeground == true ? .black.opacity(0.85) : .white
        VStack(spacing: 4) {
            HStack(spacing: 14) {
                NavigationLink { ControlView(light: light, client: client) } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "light.strip.fill").font(.system(size: 27, weight: .medium)).frame(width: 34)
                        Text(client.state?.name ?? light.name).font(.system(size: 18, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }.frame(minHeight: 48).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Toggle("Power", isOn: Binding(get: { on }, set: { value in Task { await client.brightness(value ? client.lastBrightness : 0) } }))
                    .labelsHidden().tint(.black.opacity(0.25)).disabled(client.state == nil).accessibilityLabel("\(client.state?.name ?? light.name) power")
            }.padding(.horizontal, 18).padding(.top, 13)
            BrightnessSlider(value: $level, ink: ink) { active in
                editing = active
                if !active { Task { await client.brightness(Int(level)) } }
            }.padding(.horizontal, 14).padding(.bottom, 8).disabled(client.state == nil)
                .accessibilityLabel("\(client.state?.name ?? light.name) brightness").accessibilityValue("\(Int(level / 255 * 100)) percent")
            if client.error != nil { Text("Not reachable · tap to retry").font(.caption2).padding(.bottom, 10).foregroundStyle(ink.opacity(0.7)) }
        }
        .foregroundStyle(ink)
        .background {
            RoundedRectangle(cornerRadius: 15).fill(on ? color : tileColor)
                .overlay { if on { LinearGradient(colors: [.black.opacity(0.03), .black.opacity(client.state?.usesDarkForeground == true ? 0.22 : 0.48)], startPoint: .top, endPoint: .bottom).clipShape(RoundedRectangle(cornerRadius: 15)) } }
        }
        .shadow(color: .black.opacity(0.2), radius: 8, y: 5)
        .animation(.easeInOut(duration: 0.25), value: client.state?.channels)
        .animation(.easeInOut(duration: 0.2), value: on)
        .onChange(of: client.state?.brightness) { _, value in if !editing { level = Double(value ?? 0) } }
        .task {
            while !Task.isCancelled {
                await client.refresh()
                do { try await Task.sleep(for: .seconds(4)) } catch { break }
            }
        }
    }
}

struct ControlView: View {
    let light: Light
    @ObservedObject var client: LightClient
    @Environment(\.dismiss) private var dismiss
    @State private var level = 0.0
    @State private var editing = false
    @State private var settings = false
    @State private var mode: LightMode = .color
    @State private var modeResolved = false
    @State private var editingColor = false
    var body: some View {
        let on = (client.state?.brightness ?? 0) > 0
        let ink: Color = on && client.state?.usesDarkForeground == true ? .black.opacity(0.85) : .white
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if mode != .animation {
                    ColorControls(client: client, mode: mode, isSending: $editingColor).id(mode)
                }
                SceneLibrary(client: client, mode: mode).disabled(editingColor)
                if let error = client.error { Text(error).font(.footnote).foregroundStyle(.red.opacity(0.9)).padding(.horizontal, 16) }
            }.padding(.top, 28).padding(.bottom, 28)
        }
        .background(backdrop.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: { Image(systemName: "arrow.left").font(.system(size: 19, weight: .semibold)).frame(width: 40, height: 40).background(ink.opacity(0.14), in: Circle()) }.accessibilityLabel("Back")
                    Text(client.state?.name ?? light.name).font(.system(size: 18, weight: .semibold)).lineLimit(2)
                    Spacer(minLength: 0)
                    Button { settings = true } label: { Image(systemName: "ellipsis").font(.system(size: 21, weight: .semibold)).frame(width: 40, height: 40).background(ink.opacity(0.14), in: Circle()) }.accessibilityLabel("Light settings")
                    Toggle("Power", isOn: Binding(get: { on }, set: { value in Task { await client.brightness(value ? client.lastBrightness : 0) } })).labelsHidden().tint(.black.opacity(0.28)).disabled(client.state == nil)
                }.padding(.horizontal, 16).padding(.top, 10)
                BrightnessSlider(value: $level, ink: ink) { active in editing = active; if !active { Task { await client.brightness(Int(level)) } } }
                    .disabled(client.state == nil).padding(.horizontal, 20).padding(.bottom, 12).accessibilityLabel("Brightness").accessibilityValue("\(Int(level / 255 * 100)) percent")
                HStack(spacing: 4) {
                    ForEach(LightMode.allCases) { item in
                        Button { modeResolved = true; mode = item } label: {
                            Text(item.rawValue).font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 40)
                                .background(mode == item ? ink.opacity(0.18) : .clear, in: Capsule())
                        }.buttonStyle(.plain).disabled(editingColor).accessibilityAddTraits(mode == item ? .isSelected : []).accessibilityLabel("\(item.rawValue) mode")
                    }
                }.padding(4).background(.black.opacity(0.12), in: Capsule()).padding(.horizontal, 16).padding(.bottom, 14)
            }.foregroundStyle(ink)
                .background {
                    LinearGradient(colors: [on ? (client.state?.displayColor ?? tileColor) : tileColor, on ? (client.state?.displayColor ?? tileColor).opacity(0.55) : tileColor.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                        .background(Color.black).clipShape(.rect(bottomLeadingRadius: 18, bottomTrailingRadius: 18)).ignoresSafeArea(edges: .top)
                }
                .shadow(color: .black.opacity(0.2), radius: 12, y: 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: client.state?.brightness) { _, value in if !editing { level = Double(value ?? 0) } }
        .task {
            while !Task.isCancelled {
                await client.refresh(); if !editing { level = Double(client.state?.brightness ?? 0) }
                if !modeResolved, let state = client.state {
                    do {
                        var detected: LightMode = .color
                        if let reported = state.mode {
                            detected = reported == 1 ? .gradient : reported == 2 ? .animation : .color
                        } else if !state.activeScript.isEmpty {
                            var payload = Proto(); payload.string(8, state.activeScript)
                            let response = try await client.request(6, payload: payload)
                            let script = try response.message(5)
                            detected = CustomGradient(source: script.text(3)) != nil || LightPreset.all.contains(where: { $0.isGradient && script.text(2) == "Luxio · \($0.name)" }) ? .gradient : .animation
                        }
                        if !modeResolved { mode = detected; modeResolved = true }
                    } catch { client.error = error.localizedDescription }
                }
                do { try await Task.sleep(for: .seconds(4)) } catch { break }
            }
        }
        .sheet(isPresented: $settings) { SettingsView(client: client) }
    }
}

private struct LightScene: Identifiable {
    let name: String
    let symbol: String
    let colors: [Color]
    let rgb: [Int]
    var id: String { name }
}
private let scenes: [LightScene] = [
    .init(name: "Relax", symbol: "sun.max.fill", colors: [Color(red: 1, green: 0.85, blue: 0.45), .orange], rgb: [255, 185, 80, 0, 0, 0]),
    .init(name: "Nightlight", symbol: "moon.stars.fill", colors: [.orange, Color(red: 0.4, green: 0.12, blue: 0.10)], rgb: [255, 80, 20, 0, 0, 0]),
    .init(name: "Read", symbol: "book.closed.fill", colors: [Color(red: 1, green: 0.90, blue: 0.64), .yellow], rgb: [255, 220, 160, 0, 0, 0]),
    .init(name: "Concentrate", symbol: "circle.dotted.circle", colors: [.white, .cyan], rgb: [170, 225, 255, 0, 0, 0]),
    .init(name: "Golden hour", symbol: "sun.horizon.fill", colors: [.yellow, .orange, .red], rgb: [255, 110, 25, 0, 0, 0]),
    .init(name: "Blush", symbol: "sparkles", colors: [.pink, Color(red: 0.55, green: 0.13, blue: 0.30)], rgb: [255, 65, 140, 0, 0, 0]),
    .init(name: "Ocean", symbol: "water.waves", colors: [.cyan, .blue, Color(red: 0.03, green: 0.11, blue: 0.4)], rgb: [10, 90, 255, 0, 0, 0]),
    .init(name: "Iris", symbol: "sparkle", colors: [.pink, .purple, .indigo], rgb: [125, 45, 255, 0, 0, 0]),
    .init(name: "Mint", symbol: "leaf.fill", colors: [.mint, .teal], rgb: [30, 230, 150, 0, 0, 0]),
    .init(name: "Moonlight", symbol: "moon.fill", colors: [.cyan, .indigo], rgb: [125, 175, 255, 0, 0, 0])
]

struct SceneLibrary: View {
    @ObservedObject var client: LightClient
    let mode: LightMode
    @State private var activeIsGradient = false
    @State private var busy: String?
    @State private var scriptIDs: [String: String] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if mode == .color {
            VStack(alignment: .leading, spacing: 12) {
                Text("COLORS").font(.system(size: 11, weight: .semibold)).tracking(1.8).foregroundStyle(.white.opacity(0.65)).padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: [GridItem(.fixed(116)), GridItem(.fixed(116))], spacing: 12) {
                        ForEach(scenes) { scene in
                            Button { Task { await client.color(scene.rgb) } } label: {
                                VStack(spacing: 12) {
                                    Circle().fill(LinearGradient(colors: scene.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 52, height: 52).shadow(color: .black.opacity(0.3), radius: 3, y: 3)
                                        .overlay { Image(systemName: scene.symbol).font(.system(size: 25, weight: .medium)).foregroundStyle(["Relax", "Read", "Concentrate"].contains(scene.name) ? Color.black.opacity(0.65) : .white) }
                                    Text(scene.name).font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                                }.frame(width: 106, height: 116).background(tileColor, in: RoundedRectangle(cornerRadius: 13))
                                    .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(client.state?.activeScript.isEmpty == true && client.state?.channels == scene.rgb ? Color.white.opacity(0.8) : .clear, lineWidth: 1.5) }
                            }.buttonStyle(.plain).accessibilityLabel("\(scene.name) scene")
                        }
                    }.padding(.horizontal, 14).padding(.vertical, 2)
                }
            }
            }
            if mode != .color {
                let gradient = mode == .gradient
                VStack(alignment: .leading, spacing: 12) {
                    Text(gradient ? "GRADIENTS" : "ANIMATIONS").font(.system(size: 11, weight: .semibold)).tracking(1.8).foregroundStyle(.white.opacity(0.65)).padding(.horizontal, 20)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(LightPreset.all.filter { $0.isGradient == gradient }) { preset in
                                let playing = scriptIDs[preset.name] != nil && client.state?.activeScript == scriptIDs[preset.name]
                                let colors = preset.colors.map { Color(red: Double($0[0]) / 255, green: Double($0[1]) / 255, blue: Double($0[2]) / 255) }
                                Button { Task { await runPreset(preset) } } label: {
                                    VStack(spacing: 12) {
                                        Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(width: 52, height: 52).shadow(color: .black.opacity(0.3), radius: 3, y: 3)
                                            .overlay {
                                                if busy == preset.name { ProgressView().tint(.white) }
                                                else if playing || !gradient {
                                                    Image(systemName: playing ? "stop.fill" : "play.fill").font(.system(size: 20)).foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 2)
                                                }
                                            }
                                        Text(preset.name).font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                                    }.frame(width: 106, height: 116).background(tileColor, in: RoundedRectangle(cornerRadius: 13))
                                        .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(playing ? Color.white.opacity(0.8) : .clear, lineWidth: 1.5) }
                                }.buttonStyle(.plain).disabled(busy != nil)
                                    .accessibilityLabel("\(playing ? "Stop" : "Play") \(preset.name)")
                                    .accessibilityValue(playing ? "Playing" : "")
                            }
                        }.padding(.horizontal, 14).padding(.vertical, 2)
                    }
                }
            }
            if mode == .animation, !activeIsGradient, let active = client.state?.activeScript, !active.isEmpty, !scriptIDs.values.contains(active) {
                Button { Task {
                    do { _ = try await client.request(11); client.error = nil } catch { client.error = error.localizedDescription }
                } } label: {
                    Label("Custom animation", systemImage: "stop.circle.fill").font(.headline).padding(18).frame(maxWidth: .infinity, alignment: .leading).background(tileColor, in: RoundedRectangle(cornerRadius: 13))
                }.buttonStyle(.plain).padding(.horizontal, 14).accessibilityLabel("Stop custom animation").disabled(busy != nil)
            }
        }.foregroundStyle(.white).disabled(client.state == nil || busy != nil)
            .task(id: client.state?.activeScript) {
                do {
                    activeIsGradient = false
                    if let reported = client.state?.mode { activeIsGradient = reported == 1 }
                    else if let active = client.state?.activeScript, !active.isEmpty {
                        var payload = Proto(); payload.string(8, active)
                        let response = try await client.request(6, payload: payload)
                        let script = try response.message(5)
                        activeIsGradient = CustomGradient(source: script.text(3)) != nil || LightPreset.all.contains(where: { $0.isGradient && script.text(2) == "Luxio · \($0.name)" })
                    }
                    let list = try await client.request(5)
                    for data in list[4] ?? [] {
                        let script = try Proto.decode(data)
                        for preset in LightPreset.all where script.text(2) == "Luxio · \(preset.name)" { scriptIDs[preset.name] = script.text(1) }
                    }
                } catch { if !Task.isCancelled { client.error = error.localizedDescription } }
            }
    }
    private func runPreset(_ preset: LightPreset) async {
        busy = preset.name; defer { busy = nil }
        do {
            if let id = scriptIDs[preset.name], client.state?.activeScript == id {
                _ = try await client.request(11); client.error = nil; return
            }
            let list = try await client.request(5)
            var existing: String?
            for data in list[4] ?? [] { let script = try Proto.decode(data); if script.text(2) == "Luxio · \(preset.name)" { existing = script.text(1) } }
            var script = Proto(); script.string(1, existing ?? UUID().uuidString.lowercased()); script.string(2, "Luxio · \(preset.name)"); script.string(3, preset.source); script.uint(4, preset.isGradient ? 1 : 2)
            var payload = Proto(); payload.data(7, script.bytes)
            let saved = try await client.request(existing == nil ? 7 : 8, payload: payload)
            let id = try saved.message(5).text(1); scriptIDs[preset.name] = id
            var run = Proto(); run.string(8, id); _ = try await client.request(10, payload: run); client.error = nil
        } catch { client.error = error.localizedDescription }
    }
}

struct SettingsView: View {
    @ObservedObject var client: LightClient
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var strip = "WS2805"
    @State private var count = 60
    @State private var gpio = 16
    @State private var pairing = ""
    @State private var qr = ""
    @State private var saving = false
    @State private var checkingUpdate = false
    @State private var availableBuild = 0
    @State private var installing = false
    @State private var confirmUpdate = false
    @State private var updateStatus = ""
    @State private var recoveryURL: URL?
    var body: some View {
        NavigationStack {
            Form {
                Section("Your strip") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $strip) { ForEach(["WS2805","WS2814","WS2812"], id: \.self) { Text($0) } }
                    Stepper("\(count) controllers", value: $count, in: 1...1024)
                    Stepper("Data GPIO \(gpio)", value: $gpio, in: 0...54)
                }.listRowBackground(tileColor)
                Section {
                    Button(saving ? "Saving…" : "Save changes") { Task {
                        saving = true; defer { saving = false }
                        do {
                            var config = Proto(); config.string(1,name); config.string(2,strip); config.uint(3,UInt64(count)); config.uint(4,UInt64(gpio)); config.uint(5,UInt64(client.state?.channel ?? 0))
                            var payload = Proto(); payload.data(5,config.bytes); _ = try await client.request(3,payload:payload); client.error = nil; dismiss()
                        } catch { client.error = error.localizedDescription }
                    } }.disabled(saving || client.state == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.listRowBackground(tileColor)
                Section("Firmware") {
                    Text("Build \(client.state?.build ?? 0)")
                    Text("Updates are installed only when you choose. Your light will be offline while updating.").font(.footnote).foregroundStyle(.secondary)
                    Button(checkingUpdate ? "Checking…" : "Check for updates") { Task {
                        checkingUpdate = true; availableBuild = 0; updateStatus = ""
                        defer { checkingUpdate = false }
                        do {
                            var result = try await client.request(13)
                            for _ in 0..<45 {
                                if result.number(9) == 0 { break }
                                try await Task.sleep(for: .seconds(1))
                                result = try await client.request(0)
                            }
                            guard result.number(9) == 0 else { throw LuxioError.message("Update check timed out. Try again.") }
                            guard result.text(10).isEmpty else { throw LuxioError.message(result.text(10)) }
                            availableBuild = result.number(8)
                            updateStatus = availableBuild > 0 ? "Build \(availableBuild) is available." : "You're up to date."
                            client.error = nil
                        } catch { updateStatus = error.localizedDescription }
                    } }.disabled(checkingUpdate || installing || client.state == nil)
                    if availableBuild > 0 {
                        Button("Install build \(availableBuild)") { confirmUpdate = true }.disabled(installing || checkingUpdate)
                    }
                    if installing { ProgressView("Updating your light…") }
                    if !updateStatus.isEmpty { Text(updateStatus).font(.footnote) }
                    if let recoveryURL { Link("Open recovery", destination: recoveryURL) }
                }.listRowBackground(tileColor)
                .confirmationDialog("Install firmware update?", isPresented: $confirmUpdate, titleVisibility: .visible) {
                    Button("Install update") { Task {
                        installing = true; let expectedBuild = availableBuild
                        defer { installing = false }
                        let ip = client.state?.lanIP ?? ""
                        do {
                            _ = try await client.request(14)
                            availableBuild = 0; updateStatus = "Keep your light powered on. Downloading and installing firmware…"
                            recoveryURL = ip.isEmpty ? nil : URL(string: "http://\(ip)/")
                            for _ in 0..<150 {
                                try await Task.sleep(for: .seconds(2))
                                if let result = try? await client.request(0), try result.message(3).number(2) == expectedBuild {
                                    updateStatus = "Build \(expectedBuild) installed."; recoveryURL = nil; client.error = nil; return
                                }
                                if let url = recoveryURL?.appendingPathComponent("status") {
                                    var request = URLRequest(url: url); request.timeoutInterval = 3
                                    if let (data, _) = try? await URLSession.shared.data(for: request),
                                       let status = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                        if let error = status["error"] as? String, !error.isEmpty { updateStatus = error + " Open recovery to retry."; return }
                                        if let received = status["received"] as? Int, let size = status["size"] as? Int, size > 0 {
                                            updateStatus = "Installing: \(received * 100 / size)% — keep your light powered on."
                                        }
                                    }
                                }
                            }
                            updateStatus = "The light has not reconnected yet. Open recovery to check its progress."
                        } catch { updateStatus = error.localizedDescription }
                    } }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Your light will be offline during the update. Keep it powered on until it reconnects.") }
                Section("Matter") {
                    Button("Show pairing code") { Task { do { let response = try await client.request(12); pairing = response.text(6); qr = response.text(7); client.error = nil } catch { client.error = error.localizedDescription } } }
                    if !pairing.isEmpty {
                        Text(pairing).font(.title.monospaced()).textSelection(.enabled)
                        let filter = CIFilter.qrCodeGenerator()
                        let _ = filter.setValue(Data(qr.utf8), forKey: "inputMessage")
                        if let image = filter.outputImage, let cg = CIContext().createCGImage(image.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), from: image.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) {
                            Image(uiImage: UIImage(cgImage: cg)).interpolation(.none).resizable().scaledToFit().frame(width: 180).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }.listRowBackground(tileColor)
                if let error = client.error { Section { Text(error).font(.footnote).foregroundStyle(.red) }.listRowBackground(tileColor) }
            }.scrollContentBackground(.hidden).background(backdrop).navigationTitle("Light settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.task {
            await client.refresh()
            if let state = client.state { name = state.name; strip = state.strip; count = state.count; gpio = state.gpio }
        }
    }
}
