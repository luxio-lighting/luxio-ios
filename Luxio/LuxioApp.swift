import SwiftUI
import Network
import CoreImage.CIFilterBuiltins

private let backdrop = LinearGradient(colors: [Color(red: 0.19, green: 0.105, blue: 0.13), Color(red: 0.095, green: 0.095, blue: 0.11)], startPoint: .top, endPoint: .bottom)
private let tileColor = Color(red: 0.25, green: 0.205, blue: 0.225)
private let accent = Color(red: 0.15, green: 0.48, blue: 1)

extension LightState {
    var usesDarkForeground: Bool {
        guard !previewChannels.isEmpty else { return false }
        return previewChannels.allSatisfy { channels in
            let r = Double(channels[0] + channels[3] + channels[4]) + Double(channels[5]) * 0.8
            let g = Double(channels[1] + channels[3]) + Double(channels[4]) * 0.73 + Double(channels[5]) * 0.9
            let b = Double(channels[2] + channels[3]) + Double(channels[4]) * 0.4 + Double(channels[5])
            return (min(r, 255) * 0.2126 + min(g, 255) * 0.7152 + min(b, 255) * 0.0722) / 255 > 0.68
        }
    }
}

@main struct LuxioApp: App {
    var body: some Scene { WindowGroup { LightsView().preferredColorScheme(.dark).tint(accent) } }
}

struct LightsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var discovery = Discovery()
    @State private var showAdd = false
    @State private var selectedLight: Light?
    @State private var powerStates: [String: Bool] = [:]
    @State private var failure: ActionFailure?
    var body: some View {
        NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                                if discovery.lights.isEmpty && !discovery.loading {
                                    VStack(spacing: 16) {
                                        Image(systemName: "lightbulb.slash").font(.system(size: 32)).foregroundStyle(.white.opacity(0.7))
                                            .frame(width: 76, height: 76).background(.white.opacity(0.06), in: Circle())
                                        Text("No Luxio Devices Found").font(.title3.weight(.semibold))
                                        Text("Power on Luxio nearby and enable Bluetooth, or connect it to the same Wi-Fi.")
                                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                        Button { showAdd = true } label: { Label("Add Luxio", systemImage: "plus") }
                                            .buttonStyle(.bordered).tint(.white).padding(.top, 4)
                                        Button {
                                            Task { selectedLight = await discovery.addSimulator() }
                                        } label: {
                                            Text("Try the Simulator").font(.footnote).underline().foregroundStyle(.white.opacity(0.6))
                                        }.buttonStyle(.plain).padding(.top, 4)
                                    }.frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 32)
                                        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                                        .accessibilityIdentifier("empty-lights")
                                }
                                ForEach(discovery.lights) { light in
                                    if let client = discovery.clients[light.id] {
                                        LightCard(light: light, client: client, discovery: discovery, on: powerStates[light.id] ?? client.state?.on ?? false) { selectedLight = light }.id(light.id + light.lan_ip)
                                            .onReceive(client.$failure.compactMap { $0 }) { if $0.createdAt.timeIntervalSinceNow > -6 { failure = $0 } }
                                            .onReceive(client.$state.map { $0?.on ?? false }.removeDuplicates()) { on in
                                                guard powerStates[light.id] != on else { return }
                                                withAnimation(.smooth(duration: 0.35)) { powerStates[light.id] = on }
                                            }
                                    }
                                }
                                if discovery.loading {
                                    if discovery.previousCount == 0 && discovery.lights.isEmpty {
                                        ProgressView("Finding Luxio Devices").tint(.white).font(.subheadline)
                                            .frame(maxWidth: .infinity).padding(.vertical, 48)
                                    }
                                    ForEach(0..<max(0, discovery.previousCount - discovery.lights.count), id: \.self) { index in
                                        VStack(spacing: 20) {
                                            HStack {
                                                RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.1)).frame(width: 150, height: 18)
                                                Spacer()
                                                Capsule().fill(.white.opacity(0.08)).frame(width: 48, height: 28)
                                            }
                                            Capsule().fill(.white.opacity(0.06)).frame(height: 8)
                                        }.padding(18).frame(maxWidth: .infinity)
                                            .background(tileColor.opacity(0.6), in: RoundedRectangle(cornerRadius: 15))
                                            .allowsHitTesting(false).accessibilityElement(children: .ignore)
                                            .accessibilityLabel("Loading Luxio").accessibilityIdentifier("light-skeleton-\(index)")
                                    }
                                }

                        }
                        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 24)
                    }.refreshable {
                        await discovery.refresh(includeCloud: true)
                        if !Task.isCancelled, let error = discovery.error {
                            failure = ActionFailure(title: "Find Luxio devices", message: error)
                        }
                    }
                    .modifier(ActionToast(failure: $failure))
                    .navigationDestination(isPresented: Binding(get: { selectedLight != nil }, set: { if !$0 { selectedLight = nil } })) {
                        if let light = selectedLight, let client = discovery.clients[light.id] {
                            ControlView(light: light, client: client) {
                                discovery.removeSimulator(); selectedLight = nil
                            }
                        }
                    }
                    .navigationTitle("Luxio")
                    .toolbarTitleDisplayMode(.inlineLarge)
                    .toolbar(.visible, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showAdd = true } label: { Image(systemName: "plus") }.tint(.white)
                                .accessibilityLabel("Add Device").accessibilityIdentifier("add-luxio")
                        }
                    }
                    .background(backdrop.ignoresSafeArea())
        }
        .task {
            await discovery.start()
            while !Task.isCancelled {
                if scenePhase == .active { await discovery.refresh() }
                do { try await Task.sleep(for: .seconds(4)) } catch { break }
            }
        }
        .onChange(of: scenePhase) { _, phase in discovery.setBluetoothActive(phase == .active) }
        .sheet(isPresented: $showAdd) {
            AddLuxioView(discovery: discovery) { light in
                showAdd = false; selectedLight = light
            }
        }
    }
}

struct AddLuxioView: View {
    @ObservedObject var discovery: Discovery
    var onAdded: (Light) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var connecting = false
    @State private var addingVirtual = false
    @State private var failure: ActionFailure?
    @FocusState private var addressFocused: Bool

    var body: some View {
        let host = address.trimmingCharacters(in: .whitespacesAndNewlines)
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "lightbulb.led.fill")
                            .font(.system(size: 42, weight: .medium)).foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                        VStack(spacing: 8) {
                            Text("Create your own Luxio").font(.title2.bold())
                            Text("Turn an ESP32 and an LED strip into your own smart light. Our guide will help you get started.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Link(destination: URL(string: "https://luxio.lighting/")!) {
                            HStack {
                                Text("View the Guide").fontWeight(.semibold)
                                Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold))
                            }.frame(maxWidth: .infinity).padding(.vertical, 5)
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                            .accessibilityIdentifier("add-luxio-guide")
                    }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 12)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                Section {
                    TextField("192.168.1.42", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($addressFocused).submitLabel(.go)
                        .accessibilityLabel("IP address").accessibilityIdentifier("add-luxio-address")
                        .onSubmit { if !host.isEmpty && !connecting { addressFocused = false; connecting = true } }
                    Button {
                        addressFocused = false; connecting = true
                    } label: {
                        HStack(spacing: 10) {
                            if connecting { ProgressView() }
                            Text(connecting ? "Connecting…" : "Connect")
                            Spacer()
                            if !connecting { Image(systemName: "arrow.right") }
                        }.padding(.vertical, 4)
                    }.disabled(host.isEmpty || connecting || addingVirtual).accessibilityIdentifier("add-luxio-connect")

                } header: { Text("Connect by IP address") } footer: {
                    Text("Already have a Luxio? Enter its IP address or hostname. Connect your iPhone to the same Wi-Fi network.")
                }
                Section {
                    Button {
                        addressFocused = false; addingVirtual = true
                    } label: {
                        Text("Add a virtual device").font(.footnote).underline().foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                    }.buttonStyle(.plain).accessibilityIdentifier("add-luxio-virtual")
                }.listRowBackground(Color.clear)
            }
            .navigationTitle("Add Luxio").navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }.disabled(connecting || addingVirtual)
                }
            }
            .disabled(connecting || addingVirtual)
        }
        .modifier(ActionToast(failure: $failure))
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(connecting || addingVirtual)
        .onChange(of: address) { _, _ in failure = nil }
        .task(id: connecting) {
            guard connecting else { return }
            defer { connecting = false }
            failure = nil
            await discovery.add(Light(deviceId: host, name: "Luxio", lan_ip: host))
            guard !Task.isCancelled else { return }
            if let light = discovery.lights.first(where: { $0.lan_ip == host }) { onAdded(light) }
            else { failure = ActionFailure(title: "Connect to \(host)", message: "Couldn't connect. Check the address and make sure Luxio is powered on and on the same Wi-Fi network.") }
        }
        .task(id: addingVirtual) {
            guard addingVirtual else { return }
            let light = await discovery.addSimulator()
            if !Task.isCancelled { onAdded(light) }
            addingVirtual = false
        }
    }
}

struct BrightnessSlider: View {
    @Binding var value: Double
    let ink: Color
    var onEditingChanged: (Bool) -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var dragging = false
    @State private var hapticTick = 0
    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width - 20, 1)
            let progress = min(max((value - 1) / 255, 0), 1)
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
                        if !dragging { dragging = true; hapticTick += 1; onEditingChanged(true) }
                        let next = (min(max((gesture.location.x - 10) / width, 0), 1) * 255 + 1).rounded()
                        if Int((next - 1) / 255 * 20) != Int((value - 1) / 255 * 20) { hapticTick += 1 }
                        value = next
                    }
                    .onEnded { _ in
                        guard dragging else { return }
                        dragging = false; onEditingChanged(false)
                    })
        }.frame(height: 44).opacity(enabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.12), value: dragging)
            .sensoryFeedback(.selection, trigger: hapticTick)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Brightness")
            .accessibilityValue("\(Int(value / 256 * 100)) percent")
            .accessibilityAdjustableAction { direction in
                guard enabled else { return }
                onEditingChanged(true)
                switch direction {
                case .increment: value = min(256, value + 13)
                case .decrement: value = max(1, value - 13)
                @unknown default: break
                }
                hapticTick += 1
                onEditingChanged(false)
            }
    }
}

struct LightCard: View {
    let light: Light
    @ObservedObject var client: LightClient
    let discovery: Discovery
    let on: Bool
    let open: () -> Void
    @State private var level = 0.0
    @State private var editing = false
    var body: some View {
        let ink: Color = on && client.state?.usesDarkForeground == true ? .black.opacity(0.85) : .white
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    guard client.state != nil, discovery.lights.contains(where: { $0.id == light.id && $0.lan_ip == light.lan_ip }) else { return }
                    open()
                } label: {
                    HStack(spacing: 12) {
                        if !client.isSimulator {
                            Group {
                                if client.usingBluetooth {
                                    Image("Bluetooth").resizable().scaledToFit().frame(width: 12, height: 20)
                                } else { Image(systemName: "wifi").font(.system(size: 17, weight: .medium)) }
                            }.frame(width: 22).opacity(0.8).accessibilityHidden(true)
                        }
                        Text(client.state?.name ?? light.name).font(.system(size: 18, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }.frame(minHeight: 48).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(client.state == nil)
                    .accessibilityLabel(client.state?.name ?? light.name)
                    .accessibilityValue(client.isSimulator ? "" : client.usingBluetooth ? "Connected via Bluetooth" : "Connected via Wi-Fi")
                Toggle("Power", isOn: Binding(get: { on }, set: { value in Task { await client.power(value) } }))
                    .labelsHidden().tint(.black.opacity(0.25)).disabled(client.state == nil).accessibilityLabel("\(client.state?.name ?? light.name) power")
            }.padding(.horizontal, 18).padding(.top, 13)
            BrightnessSlider(value: $level, ink: ink) { active in
                editing = active
                if !active { Task { await client.brightness(Int(level)) } }
            }.padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 8)
                .opacity(on ? 1 : 0)
                .frame(height: 56, alignment: .top)
                .allowsHitTesting(on).accessibilityHidden(!on)
                .accessibilityLabel("\(client.state?.name ?? light.name) brightness").accessibilityValue("\(Int(level / 256 * 100)) percent")
        }
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(ink)
        .background {
            LiveLightBackdrop(client: client)
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.03), .black.opacity(client.state?.usesDarkForeground == true ? 0.22 : 0.48)], startPoint: .top, endPoint: .bottom)
                        .opacity(on ? 1 : 0)
                }
        }
        // Keep the contents at their expanded size and reveal the whole card together.
        .frame(height: on ? 117 : 74, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 5)
        .onChange(of: client.state?.brightness) { _, value in if !editing { level = Double(value ?? 16) } }
        .onAppear { level = Double(client.state?.brightness ?? 16) }
    }
}

struct ControlView: View {
    @Environment(\.dismiss) private var dismiss
    let light: Light
    @ObservedObject var client: LightClient
    let removeSimulator: (() -> Void)?
    @State private var level = 0.0
    @State private var editing = false
    @State private var settings = false
    @State private var mode: LightMode = .color
    @State private var modeResolved = false
    @State private var editingColor = false
    @StateObject private var colorEditor: ColorEditor
    init(light: Light, client: LightClient, removeSimulator: (() -> Void)? = nil) {
        self.light = light; self.client = client; self.removeSimulator = removeSimulator
        _level = State(initialValue: Double(client.state?.brightness ?? 16))
        let reported = client.state?.mode ?? 0
        _mode = State(initialValue: reported == 1 && client.state?.supportsGradients == true ? .gradient : reported == 2 ? .animation : .color)
        _modeResolved = State(initialValue: client.state != nil)
        _colorEditor = StateObject(wrappedValue: ColorEditor(client: client))
    }
    var body: some View {
        let on = client.state?.on ?? false
        let ink: Color = on && client.state?.usesDarkForeground == true ? .black.opacity(0.85) : .white
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if client.usingBluetooth, client.state?.lanIP.isEmpty != false || client.state?.lanIP == "0.0.0.0" {
                    NavigationLink {
                        WifiSetupView(client: client)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "wifi").font(.title3)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Connect to Wi-Fi").font(.subheadline.weight(.semibold))
                                Text(client.state?.supportsMatter == false ? "Control Luxio over your network." : "Control Luxio over your network and add it to Matter.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        }.foregroundStyle(.white).padding(16)
                            .background(tileColor, in: RoundedRectangle(cornerRadius: 15))
                    }.buttonStyle(.plain).padding(.horizontal, 16)
                }
                if mode != .animation {
                    ColorControls(client: client, editor: colorEditor, mode: mode, isSending: $editingColor).id("\(mode.rawValue)-\(client.state?.strip ?? "")")
                }
                SceneLibrary(client: client, editor: colorEditor, mode: mode).allowsHitTesting(!editingColor)

            }.padding(.top, 28).padding(.bottom, 28)
        }.refreshable {
            let minimum = ContinuousClock.now.advanced(by: .milliseconds(500))
            client.libraryRevision += 1; await client.refresh(userInitiated: true)
            try? await Task.sleep(until: minimum, clock: .continuous)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                BrightnessSlider(value: $level, ink: ink) { active in editing = active; if !active { Task { await client.brightness(Int(level)) } } }
                    .disabled(client.state == nil).padding(.horizontal, 20).padding(.bottom, 4).accessibilityLabel("Brightness").accessibilityValue("\(Int(level / 256 * 100)) percent")
                let picker = Picker("Mode", selection: Binding(get: { mode }, set: { if !editingColor { modeResolved = true; mode = $0 } })) {
                    ForEach(LightMode.allCases.filter { $0 != .gradient || client.state?.supportsGradients == true }) { item in
                        Text(item.rawValue).tag(item)
                    }
                }.pickerStyle(.segmented).controlSize(.large).labelsHidden()
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .allowsHitTesting(!editingColor).accessibilityIdentifier("Light mode")
                Group {
                    if #available(iOS 26.0, *) {
                        picker.glassEffect(.regular, in: .capsule)
                    } else {
                        picker.background(.regularMaterial, in: Capsule())
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }.foregroundStyle(ink)
                .background {
                    LiveLightBackdrop(client: client)
                        .overlay { LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom) }
                        .clipShape(.rect(bottomLeadingRadius: 18, bottomTrailingRadius: 18)).ignoresSafeArea(edges: .top)
                }
                .shadow(color: .black.opacity(0.2), radius: 12, y: 8)
        }
        .background(backdrop.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .background(InteractiveBackGesture().frame(width: 0, height: 0))
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(on && client.state?.usesDarkForeground == true ? .light : .dark, for: .navigationBar)
        .tint(ink)
        .toolbar {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(ink).frame(width: 31, height: 31)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Back")
                }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarLeading) {
                    Text(client.state?.name ?? light.name).font(.headline).lineLimit(1)
                        .frame(maxWidth: 160, alignment: .leading).fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(ink)
                        .accessibilityIdentifier("device-title")
                }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Button { settings = true } label: {
                        Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(ink).frame(width: 31, height: 31)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Luxio settings")
                }.sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(ink).frame(width: 31, height: 31)
                            .background(.regularMaterial, in: Circle())
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Back")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Text(client.state?.name ?? light.name).font(.headline).lineLimit(1)
                        .frame(maxWidth: 160, alignment: .leading).fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(ink)
                        .accessibilityIdentifier("device-title")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { settings = true } label: {
                        Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(ink).frame(width: 31, height: 31)
                            .background(.regularMaterial, in: Circle())
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Luxio settings")
                }
            }
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle("Power", isOn: Binding(get: { on }, set: { value in Task { await client.power(value) } }))
                        .toggleStyle(.switch).labelsHidden().tint(.black.opacity(0.28)).disabled(client.state == nil)
                }.sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle("Power", isOn: Binding(get: { on }, set: { value in Task { await client.power(value) } }))
                        .toggleStyle(.switch).labelsHidden().tint(.black.opacity(0.28)).disabled(client.state == nil)
                }
            }
        }
        .onChange(of: client.state?.count) { _, count in
            if (count ?? 0) <= 1 && mode == .gradient { mode = .color }
        }
        .onChange(of: client.state?.brightness) { _, value in if !editing { level = Double(value ?? 16) } }
        .task {
            while !Task.isCancelled {
                await client.refresh(); if !editing { level = Double(client.state?.brightness ?? 16) }
                if !modeResolved, let state = client.state {
                    let reported = state.mode ?? 0
                    mode = reported == 1 && state.supportsGradients ? .gradient : reported == 2 ? .animation : .color
                    modeResolved = true
                }
                do { try await Task.sleep(for: .seconds(4)) } catch { break }
            }
        }
        .modifier(ActionToast(failure: $client.failure))
        .sheet(isPresented: $settings) { SettingsView(client: client, removeSimulator: removeSimulator) }
    }
}

private struct LightScene: Identifiable {
    let name: String
    let rgb: [Int]
    var id: String { name }
}
// Ordered by RGB hue, from red through green and blue back to rose.
private let scenes: [LightScene] = [
    .init(name: "Ruby", rgb: [255, 0, 0, 0, 0, 0]),
    .init(name: "Coral", rgb: [255, 100, 80, 0, 0, 0]),
    .init(name: "Nightlight", rgb: [255, 80, 20, 0, 0, 0]),
    .init(name: "Golden hour", rgb: [255, 110, 25, 0, 0, 0]),
    .init(name: "Amber", rgb: [255, 150, 0, 0, 0, 0]),
    .init(name: "Relax", rgb: [255, 185, 80, 0, 0, 0]),
    .init(name: "Read", rgb: [255, 220, 160, 0, 0, 0]),
    .init(name: "Sunshine", rgb: [255, 225, 0, 0, 0, 0]),
    .init(name: "Lemon", rgb: [235, 255, 40, 0, 0, 0]),
    .init(name: "Lime", rgb: [145, 255, 30, 0, 0, 0]),
    .init(name: "Green", rgb: [30, 255, 35, 0, 0, 0]),
    .init(name: "Emerald", rgb: [0, 255, 110, 0, 0, 0]),
    .init(name: "Mint", rgb: [30, 230, 150, 0, 0, 0]),
    .init(name: "Turquoise", rgb: [0, 255, 220, 0, 0, 0]),
    .init(name: "Cyan", rgb: [0, 255, 255, 0, 0, 0]),
    .init(name: "Concentrate", rgb: [170, 225, 255, 0, 0, 0]),
    .init(name: "Moonlight", rgb: [125, 175, 255, 0, 0, 0]),
    .init(name: "Ocean", rgb: [10, 90, 255, 0, 0, 0]),
    .init(name: "Blue", rgb: [30, 30, 255, 0, 0, 0]),
    .init(name: "Iris", rgb: [125, 45, 255, 0, 0, 0]),
    .init(name: "Violet", rgb: [175, 30, 255, 0, 0, 0]),
    .init(name: "Magenta", rgb: [255, 30, 220, 0, 0, 0]),
    .init(name: "Blush", rgb: [255, 65, 140, 0, 0, 0]),
    .init(name: "Rose", rgb: [255, 30, 70, 0, 0, 0])
]

struct SavedLightItem: Identifiable {
    let id: String
    let name: String
    let mode: Int
    var preview: [[Int]] = []
}

private struct ExpandedAnimationCard: LayoutValueKey {
    static let defaultValue = false
}

private struct AnimationCardLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let columns = max(1, Int((width + 12) / 116))
        let rows = (subviews.count + columns - 1) / columns
        return CGSize(width: width, height: rows == 0 ? 0 : Double(rows) * 128 - 12)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = max(1, Int((bounds.width + 12) / 116))
        let cell = (bounds.width - Double(columns - 1) * 12) / Double(columns)
        for start in stride(from: 0, to: subviews.count, by: columns) {
            let row = subviews[start..<min(start + columns, subviews.count)]
            let expanded = row.contains { $0[ExpandedAnimationCard.self] }
            let extra = expanded ? (row.count > 1 ? min(44, max(0, cell - 72) * Double(row.count - 1)) : min(44, bounds.width - cell)) : 0
            var x = bounds.minX
            for view in row {
                let itemWidth = cell + (view[ExpandedAnimationCard.self] ? extra : -extra / Double(max(1, row.count - 1)))
                view.place(at: CGPoint(x: x, y: bounds.minY + Double(start / columns) * 128), anchor: .topLeading, proposal: ProposedViewSize(width: itemWidth, height: 116))
                x += itemWidth + 12
            }
        }
    }
}

struct SceneLibrary: View {
    @ObservedObject var client: LightClient
    @ObservedObject var editor: ColorEditor
    let mode: LightMode
    @State private var busy: Set<String> = []
    @State private var selectionTask: Task<Void, Never>?
    @State private var savedItems: [SavedLightItem] = []
    @State private var libraryLoaded = false
    @State private var search = ""
    @State private var deleting: SavedLightItem?
    @State private var renaming: SavedLightItem?
    @State private var renamedName = ""
    @State private var namingPreset = false
    @State private var presetName = ""
    @State private var savingPreset = false
    @State private var animationSettings: (title: String, scriptId: String, scriptName: String)?
    var body: some View {
        let items = savedItems.filter { $0.mode == (mode == .color ? 0 : mode == .gradient ? 1 : 2) }
        let gradient = mode == .gradient
        VStack(alignment: .leading, spacing: 12) {
            Text("Presets").font(.headline).padding(.horizontal, 6)
            AnimationCardLayout {
                if mode == .color {
                    ForEach(scenes) { scene in
                        Button {
                            let key = "color-\(scene.name)"
                            guard busy.insert(key).inserted else { return }
                            let previous = selectionTask
                            selectionTask = Task {
                                await previous?.value
                                defer { busy.remove(key) }
                                await client.color(scene.rgb)
                            }
                        } label: {
                            VStack(spacing: 12) {
                                Circle().fill(Color(red: Double(scene.rgb[0]) / 255, green: Double(scene.rgb[1]) / 255, blue: Double(scene.rgb[2]) / 255))
                                    .frame(width: 52, height: 52).shadow(color: .black.opacity(0.3), radius: 3, y: 3)
                                    .overlay {
                                        if busy.contains("color-\(scene.name)") { ProgressView().tint(.white) }
                                    }
                                Text(scene.name).font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                            }.frame(maxWidth: .infinity).frame(height: 116).background(tileColor, in: RoundedRectangle(cornerRadius: 13))
                                .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(client.state?.mode == 0 && client.state?.channels == scene.rgb ? Color.white.opacity(0.8) : .clear, lineWidth: 1.5) }
                        }.buttonStyle(.plain).disabled(busy.contains("color-\(scene.name)"))
                            .accessibilityIdentifier("color-\(scene.name)").accessibilityLabel("\(scene.name) scene")
                            .accessibilityValue(busy.contains("color-\(scene.name)") ? "Loading" : client.state?.mode == 0 && client.state?.channels == scene.rgb ? "Selected" : "")
                    }
                } else {
                    ForEach(LightPreset.all.filter { $0.isGradient == gradient }) { preset in
                        let playing = preset.isGradient ? (client.state?.mode == 1 && (client.state?.gradient?[3] ?? []).compactMap { try? Proto.decode($0) }.map { c in (1...3).map { c.number($0) } } == preset.colors) : (client.state?.mode == 2 && client.state?.scriptName == "Luxio · \(preset.name)")
                        let colors = preset.previewColors.map { Color(red: Double($0[0]) / 255, green: Double($0[1]) / 255, blue: Double($0[2]) / 255) }
                        let options = !preset.isGradient && playing && !(client.state?.parameters.isEmpty ?? true)
                        HStack(spacing: 0) {
                        Button {
                            guard busy.insert(preset.name).inserted else { return }
                            let previous = selectionTask
                            selectionTask = Task {
                                await previous?.value
                                defer { busy.remove(preset.name) }
                                await runPreset(preset)
                            }
                        } label: {
                            VStack(spacing: 12) {
                                Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 52, height: 52).shadow(color: .black.opacity(0.3), radius: 3, y: 3)
                                    .overlay {
                                        if busy.contains(preset.name) { ProgressView().tint(.white) }
                                    }
                                Text(preset.name).font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                            }.frame(maxWidth: .infinity).frame(height: 116).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(busy.contains(preset.name))
                            .accessibilityIdentifier("preset-\(preset.name)")
                            .accessibilityLabel("\(gradient ? "Apply" : "Play") \(preset.name)")
                            .accessibilityValue(busy.contains(preset.name) ? "Loading" : playing ? (gradient ? "Selected" : "Playing") : "")
                        if options {
                            Button {
                                animationSettings = (preset.name, client.state?.activeScript ?? "", client.state?.scriptName ?? "")
                            } label: {
                                Image(systemName: "slider.horizontal.3").font(.system(size: 19, weight: .medium))
                                    .frame(width: 44, height: 72).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("Settings for \(preset.name)")
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                        }.background(tileColor, in: RoundedRectangle(cornerRadius: 13))
                            .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(playing ? Color.white.opacity(0.8) : .clear, lineWidth: 1.5) }
                            .layoutValue(key: ExpandedAnimationCard.self, value: options)
                            .contextMenu {
                                Button("Save to device", systemImage: "square.and.arrow.down") { Task {
                                    guard busy.insert(preset.name).inserted else { return }
                                    defer { busy.remove(preset.name) }
                                    do {
                                        var payload = Proto()
                                        if preset.isGradient {
                                            payload.data(11, try CustomGradient(points: preset.colors.map { GradientPoint(channels: $0 + [0, 0, 0]) }).proto(strip: client.state?.strip ?? "WS2805", name: preset.name).bytes)
                                            _ = try await client.request(20, payload: payload)
                                        } else {
                                            guard (client.state?.build ?? 0) >= 21 else { throw LuxioError.message("These animation presets require firmware build 21 or newer.") }
                                            var script = Proto(); script.string(2, preset.name); script.string(3, preset.source); script.uint(4, 2)
                                            payload.data(7, script.bytes); _ = try await client.request(7, payload: payload)
                                        }
                                        client.libraryRevision += 1; client.error = nil
                                    } catch { client.report(error, action: "Save preset") }
                                } }
                            }
                    }
                }
            }
            .animation(.smooth(duration: 0.3), value: "\(client.state?.mode ?? 0)-\(client.state?.activeScript ?? "")-\(client.state?.scriptName ?? "")-\(client.state?.parameters.isEmpty ?? true)")
            Text("Saved").font(.headline).padding(.horizontal, 6).padding(.top, 16)
            if libraryLoaded && items.isEmpty {
                Group {
                    if mode == .animation {
                        Text("No saved animations yet. To create your own animations, try [Luxio Studio](https://studio.luxio.lighting).")
                            .tint(.white.opacity(0.75))
                    } else {
                        Text(mode == .color ? "No saved colors yet." : "No saved gradients yet.")
                    }
                }
                .font(.subheadline).foregroundStyle(.white.opacity(0.55)).padding(.horizontal, 6)
                .accessibilityIdentifier("saved-empty-state")
            }
            if items.count > 8 {
                TextField("Search saved items", text: $search).padding(12).background(tileColor, in: RoundedRectangle(cornerRadius: 12))
            }
            AnimationCardLayout {
                ForEach(items.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { item in
                    let playing = (item.mode == 0 ? client.state?.activeColor : item.mode == 1 ? client.state?.activeGradient : client.state?.activeScript) == item.id
                    let options = item.mode == 2 && client.state?.mode == 2 && playing && !(client.state?.parameters.isEmpty ?? true)
                    HStack(spacing: 0) {
                    Button {
                        guard busy.insert(item.id).inserted else { return }
                        let previous = selectionTask
                        selectionTask = Task {
                            await previous?.value
                            defer { busy.remove(item.id) }
                            do {
                                if item.mode == 2 && client.state?.mode == 2 && client.state?.activeScript == item.id && client.state?.on == true { return }
                                var payload = Proto(); payload.string(item.mode == 0 ? 15 : item.mode == 1 ? 12 : 8, item.id)
                                _ = try await client.request(item.mode == 0 ? 30 : item.mode == 1 ? 23 : 10, payload: payload)
                                if item.mode == 2, let state = client.state,
                                   let data = UserDefaults.standard.data(forKey: "luxio.animation-settings.\(state.deviceId).saved.\(item.id)"),
                                   let cached = try? Proto.decode(data) {
                                    var patch = Proto(); patch.string(8, item.id)
                                    for bytes in cached[17] ?? [] {
                                        guard let fields = try? Proto.decode(bytes) else { continue }
                                        let value = AnimationParameter(fields)
                                        if let definition = state.parameters.first(where: { $0.name == value.name && $0.boolean == value.boolean }),
                                           value.value.isFinite, value.value >= definition.minimum, value.value <= definition.maximum,
                                           !value.boolean || value.value == 0 || value.value == 1 { patch.data(17, value.proto.bytes) }
                                    }
                                    if !state.parameters.isEmpty { _ = try await client.request(32, payload: patch) }
                                }
                                client.error = nil
                            } catch { client.report(error, action: "Apply preset") }
                        }
                    } label: {
                        VStack(spacing: 12) {
                            LightBackdrop(channels: item.preview, startPoint: .topLeading, endPoint: .bottomTrailing)
                                .clipShape(Circle()).frame(width: 52, height: 52)
                                .shadow(color: .black.opacity(0.3), radius: 3, y: 3)
                                .overlay {
                                    if busy.contains(item.id) { ProgressView().tint(.white) }
                                }
                            Text(item.name).font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                        }.frame(maxWidth: .infinity).frame(height: 116).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(busy.contains(item.id)).accessibilityLabel("\(item.mode < 2 ? "Apply" : "Play") \(item.name)")
                        .accessibilityValue(busy.contains(item.id) ? "Loading" : playing ? (item.mode < 2 ? "Selected" : "Playing") : "")
                        .task(id: "\(item.id)-\(client.libraryRevision)-\(item.preview.isEmpty)") {
                            guard item.mode < 2, item.preview.isEmpty else { return }
                            do {
                                var payload = Proto(); payload.string(item.mode == 0 ? 15 : 12, item.id)
                                let response = try await client.request(item.mode == 0 ? 26 : 19, payload: payload)
                                let detail = try response.message(item.mode == 0 ? 19 : 16)
                                let preview = try (detail[3] ?? []).map { data in
                                    let color = try Proto.decode(data); return (1...6).map { color.number($0) }
                                }
                                if !Task.isCancelled, let index = savedItems.firstIndex(where: { $0.id == item.id }) {
                                    savedItems[index].preview = preview
                                }
                            } catch { if !Task.isCancelled && !(error is CancellationError) && (error as? URLError)?.code != .cancelled { client.error = error.localizedDescription } }
                        }
                    if options {
                        Button {
                            animationSettings = (item.name, client.state?.activeScript ?? "", client.state?.scriptName ?? "")
                        } label: {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 19, weight: .medium))
                                .frame(width: 44, height: 72).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Settings for \(item.name)")
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                    }.background(tileColor, in: RoundedRectangle(cornerRadius: 13))
                        .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(playing ? Color.white.opacity(0.8) : .clear, lineWidth: 1.5) }
                        .layoutValue(key: ExpandedAnimationCard.self, value: options)
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") {
                                renamedName = item.name; renaming = item
                            }
                            Button(role: .destructive) { deleting = item } label: {
                                Label("Delete", systemImage: "trash").foregroundStyle(.red)
                            }.tint(.red)
                        }
                }
                if mode != .animation {
                    Button { presetName = ""; namingPreset = true } label: {
                        VStack(spacing: 12) {
                            Circle().fill(.white.opacity(0.08)).frame(width: 52, height: 52)
                                .overlay {
                                    if savingPreset { ProgressView().tint(.white) }
                                    else {
                                        Image(systemName: "plus").font(.system(size: 24, weight: .medium)).foregroundStyle(.white)
                                    }
                                }
                            Text("Save").font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                        }.frame(maxWidth: .infinity).frame(height: 116).background(tileColor, in: RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(.plain).accessibilityIdentifier("save-preset")
                        .accessibilityLabel("Save")
                        .disabled(editor.loading || editor.loadFailed || savingPreset || !busy.isEmpty).allowsHitTesting(!editor.sending)
                }
            }.animation(.smooth(duration: 0.3), value: items.map(\.id))
                .animation(.smooth(duration: 0.3), value: "\(client.state?.mode ?? 0)-\(client.state?.activeScript ?? "")-\(client.state?.parameters.isEmpty ?? true)")
            if mode == .animation && (!libraryLoaded || !items.isEmpty) {
                Text("To create your own animations, try [Luxio Studio](https://studio.luxio.lighting).")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.55)).tint(.white.opacity(0.75))
                    .padding(.horizontal, 6).padding(.top, 4)
                    .accessibilityIdentifier("studio-hint")
            }
        }.padding(.horizontal, 14).padding(.vertical, 2).foregroundStyle(.white).disabled(client.state == nil)
            .sheet(isPresented: Binding(get: { animationSettings != nil }, set: { if !$0 { animationSettings = nil } })) {
                if let settings = animationSettings {
                    AnimationParameterControls(client: client, title: settings.title, scriptId: settings.scriptId, scriptName: settings.scriptName)
                        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                }
            }
            .alert(gradient ? "Save Gradient" : "Save Color", isPresented: $namingPreset) {
                TextField("Name", text: $presetName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    let points = editor.points
                    let strip = editor.strip
                    let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let savedMode = gradient ? 1 : 0
                    savingPreset = true
                    Task {
                        defer { savingPreset = false }
                        do {
                            var payload = Proto()
                            let detail: [Int: [Data]]
                            if savedMode == 1 {
                                payload.data(11, try CustomGradient(points: points).proto(strip: strip, name: name).bytes)
                                detail = try await client.request(20, payload: payload).message(16)
                            } else {
                                var color = Proto(); for (i, value) in points[0].channels(strip: strip).enumerated() { color.uint(i + 1, UInt64(value)) }
                                var saved = Proto(); saved.string(2, name); saved.data(3, color.bytes)
                                payload.data(14, saved.bytes)
                                detail = try await client.request(27, payload: payload).message(19)
                            }
                            let item = SavedLightItem(id: detail.text(1), name: name, mode: savedMode, preview: points.map { $0.channels(strip: strip) })
                            savedItems.append(item); search = ""
                            client.libraryRevision += 1; client.error = nil
                        } catch { client.report(error, action: "Save preset") }
                    }
                }.disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || presetName.utf8.count > 63)
            } message: { Text("Save a copy on \(client.state?.name ?? client.address).") }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renamedName)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Save") {
                    guard let item = renaming else { return }; renaming = nil
                    let name = renamedName.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        guard busy.insert(item.id).inserted else { return }; defer { busy.remove(item.id) }
                        do {
                            var lookup = Proto(); lookup.string(item.mode == 0 ? 15 : item.mode == 1 ? 12 : 8, item.id)
                            let response = try await client.request(item.mode == 0 ? 26 : item.mode == 1 ? 19 : 6, payload: lookup)
                            let detail = try response.message(item.mode == 0 ? 19 : item.mode == 1 ? 16 : 5)
                            guard detail.text(1) == item.id else { throw LuxioError.message("Saved item not found") }
                            var saved = Proto(); saved.string(1, item.id); saved.string(2, name)
                            // Keep the stored content intact; only the name changes.
                            for value in detail[3] ?? [] { saved.data(3, value) }
                            if item.mode == 1 {
                                for metadata in detail[4] ?? [] { saved.data(4, metadata) }
                            } else if item.mode == 2 {
                                saved.uint(4, UInt64(detail.number(4)))
                                for parameter in detail[5] ?? [] { saved.data(5, parameter) }
                                for color in detail[6] ?? [] { saved.data(6, color) }
                            }
                            var payload = Proto(); payload.data(item.mode == 0 ? 14 : item.mode == 1 ? 11 : 7, saved.bytes)
                            _ = try await client.request(item.mode == 0 ? 28 : item.mode == 1 ? 21 : 8, payload: payload)
                            if let index = savedItems.firstIndex(where: { $0.id == item.id }) {
                                savedItems[index] = SavedLightItem(id: item.id, name: name, mode: item.mode, preview: savedItems[index].preview)
                            }
                            search = ""; client.libraryRevision += 1; client.error = nil
                        } catch { client.report(error, action: "Rename preset") }
                    }
                }.disabled(renamedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || renamedName.utf8.count > 63)
            }
            .alert("Delete saved item?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Cancel", role: .cancel) { deleting = nil }
                Button("Delete", role: .destructive) {
                    guard let item = deleting else { return }; deleting = nil
                    Task {
                        guard busy.insert(item.id).inserted else { return }; defer { busy.remove(item.id) }
                        do {
                            var payload = Proto(); payload.string(item.mode == 0 ? 15 : item.mode == 1 ? 12 : 8, item.id)
                            _ = try await client.request(item.mode == 0 ? 29 : item.mode == 1 ? 22 : 9, payload: payload)
                            savedItems.removeAll { $0.id == item.id }; client.libraryRevision += 1; client.error = nil
                        } catch { client.report(error, action: "Delete preset") }
                    }
                }
            } message: { Text("This removes it from the device.") }
            .onChange(of: mode) { _, _ in search = "" }
            .task(id: "\(mode.rawValue)-\(client.state?.count ?? 0)-\(client.libraryRevision)") {
                do {
                    var items: [SavedLightItem] = []
                    for (operation, field, mode) in [(25, 18, 0), (18, 15, 1), (5, 4, 2)] {
                        if operation == 18 && client.state?.supportsGradients != true { continue }
                        let list = try await client.request(operation)
                        for data in list[field] ?? [] {
                            let item = try Proto.decode(data)
                            let preview = try (item[mode == 2 ? 6 : 3] ?? []).map { data in
                                let color = try Proto.decode(data); return (1...6).map { color.number($0) }
                            }
                            items.append(SavedLightItem(id: item.text(1), name: item.text(2), mode: mode, preview: preview))
                        }
                    }
                    if !Task.isCancelled {
                        let incoming = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
                        let retained = savedItems.compactMap { old -> SavedLightItem? in
                            guard var item = incoming[old.id] else { return nil }
                            if item.preview.isEmpty { item.preview = old.preview }
                            return item
                        }
                        let retainedIDs = Set(retained.map(\.id))
                        savedItems = retained + items.filter { !retainedIDs.contains($0.id) }
                        libraryLoaded = true
                    }
                } catch { if !Task.isCancelled && !(error is CancellationError) && (error as? URLError)?.code != .cancelled { client.error = error.localizedDescription } }
            }
    }
    private func runPreset(_ preset: LightPreset) async {
        do {
            if !preset.isGradient && client.state?.mode == 2 && client.state?.scriptName == "Luxio · \(preset.name)" && client.state?.on == true && (!preset.source.contains("-- @parameter") || !(client.state?.parameters.isEmpty ?? true)) {
                return
            }
            if preset.isGradient {
                let points = preset.colors.map { GradientPoint(channels: $0 + [0, 0, 0]) }
                var payload = Proto(); payload.data(11, try CustomGradient(points: points).proto(strip: client.state?.strip ?? "WS2805").bytes)
                _ = try await client.request(17, payload: payload)
            } else {
                guard (client.state?.build ?? 0) >= 21 else { throw LuxioError.message("These animation presets require firmware build 21 or newer.") }
                var script = Proto(); script.string(2, "Luxio · \(preset.name)"); script.string(3, preset.source); script.uint(4, 2)
                var payload = Proto(); payload.data(7, script.bytes); _ = try await client.request(31, payload: payload)
                if let state = client.state,
                   let data = UserDefaults.standard.data(forKey: "luxio.animation-settings.\(state.deviceId).preset.\(state.scriptName)"),
                   let cached = try? Proto.decode(data) {
                    var patch = Proto(); var active = Proto(); active.string(2, state.scriptName); patch.data(7, active.bytes)
                    for bytes in cached[17] ?? [] {
                        guard let fields = try? Proto.decode(bytes) else { continue }
                        let value = AnimationParameter(fields)
                        if let definition = state.parameters.first(where: { $0.name == value.name && $0.boolean == value.boolean }),
                           value.value.isFinite, value.value >= definition.minimum, value.value <= definition.maximum,
                           !value.boolean || value.value == 0 || value.value == 1 { patch.data(17, value.proto.bytes) }
                    }
                    if !state.parameters.isEmpty { _ = try await client.request(32, payload: patch) }
                }
            }
            client.error = nil
        } catch { client.report(error, action: "Apply preset") }
    }
}

struct FirmwareUpdateView: View {
    @ObservedObject var client: LightClient
    let build: Int
    @Binding var installing: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var complete = false
    @State private var progress: Double?
    @State private var status = "Preparing Luxio…"
    @State private var error: String?
    @State private var recoveryURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: complete ? "checkmark.circle.fill" : error != nil ? "exclamationmark.circle" : "arrow.down.circle")
                            .font(.system(size: 42, weight: .medium))
                            .foregroundStyle(complete ? Color.green : error != nil ? Color.orange : Color.accentColor)
                            .accessibilityHidden(true)
                        VStack(spacing: 8) {
                            Text(complete ? "Update Installed" : error != nil ? "Update Interrupted" : installing ? "Installing Update" : "Update Available")
                                .font(.title2.bold())
                            Text(complete ? "Luxio is now running build \(build)." : installing ? "Keep Luxio powered on while the update installs." : error != nil ? "Keep Luxio powered on. Check its connection or open recovery to continue." : "Build \(build) is ready to install. Luxio will briefly go offline during the update.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if installing {
                            VStack(spacing: 12) {
                                if let progress {
                                    ProgressView(value: progress).accessibilityLabel("Update progress")
                                        .accessibilityValue("\(Int(progress * 100)) percent")
                                    Text("\(Int(progress * 100))% downloaded").monospacedDigit()
                                        .accessibilityIdentifier("update-progress")
                                } else {
                                    ProgressView().accessibilityLabel("Installing firmware")
                                }
                                Text(status).font(.subheadline).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("update-status")
                            }.padding(.top, 8)
                        }
                    }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 20)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                if error != nil, let recoveryURL { Section { Link("Open Recovery", destination: recoveryURL) } }
            }
            .navigationTitle("Firmware Update").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !installing && !complete && error == nil {
                    ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !installing {
                    Button {
                        if complete || error != nil { dismiss() }
                        else { installing = true }
                    } label: {
                        Text(complete ? "Done" : error != nil ? "Close" : "Install")
                            .fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 5)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                        .accessibilityIdentifier(complete ? "update-done" : error != nil ? "update-close" : "update-install")
                        .padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
                }
            }
        }
        .modifier(ActionToast(failure: $client.failure))
        .onChange(of: error) { _, message in
            if let message { client.report(LuxioError.message(message), action: "Install update") }
        }
        .presentationDetents(error == nil ? [.medium, .large] : [.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(installing)
        .task(id: installing) {
            guard installing else { return }
            defer { installing = false }
            let ip = client.state?.lanIP ?? ""
            recoveryURL = ip.isEmpty || ip == "0.0.0.0" ? nil : URL(string: "http://\(ip)/")
            do {
                _ = try await client.request(14)
                status = "Waiting for Luxio to restart…"
                let deadline = ContinuousClock.now.advanced(by: .seconds(300))
                while ContinuousClock.now < deadline {
                    try await Task.sleep(for: .seconds(2))
                    if let url = recoveryURL?.appendingPathComponent("status") {
                        var request = URLRequest(url: url); request.timeoutInterval = 3
                        if let (data, response) = try? await URLSession.shared.data(for: request),
                           (response as? HTTPURLResponse)?.statusCode == 200,
                           let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           state["build"] as? Int == build {
                            if let failure = state["error"] as? String, !failure.isEmpty { throw LuxioError.message(failure) }
                            if let received = state["received"] as? Int, let size = state["size"] as? Int, size > 0 {
                                progress = min(1, max(0, Double(received) / Double(size)))
                                status = received >= size ? "Verifying firmware and restarting Luxio…" : "Downloading firmware…"
                            }
                        }
                    }
                    if let result = try? await client.request(0, timeout: 2), try result.message(3).number(2) == build {
                        complete = true; client.error = nil; return
                    }
                    try Task.checkCancellation()
                }
                error = "Luxio has not reconnected yet. The update may still be running."
            } catch {
                if !Task.isCancelled && !(error is CancellationError) && (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var client: LightClient
    var removeSimulator: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var strip = "WS2805"
    @State private var count = "60"
    @State private var gpio = "16"
    @State private var wifiEnabled = true
    @State private var matterEnabled = true
    @State private var confirmDisableWifi = false
    @State private var relayEnabled = false
    @State private var relayGPIO = "0"
    @State private var relayInverted = false
    @State private var pairing = ""
    @State private var qr = ""
    @State private var copiedPairing = false
    @State private var configureWifi = false
    @FocusState private var focusedField: String?
    @State private var saving = false
    @State private var checkingUpdate = false
    @State private var upToDate = false
    @State private var availableBuild = 0
    @State private var installing = false
    @State private var showUpdate = false
    var body: some View {
        let validCount = Int(count).map { (1...1024).contains($0) } ?? false
        let validGPIO = Int(gpio).map { (0...54).contains($0) } ?? false
        let validRelayGPIO = !relayEnabled || (Int(relayGPIO).map { (0...54).contains($0) && $0 != Int(gpio) } ?? false)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        NavigationStack {
            Form {
                if !client.isSimulator {
                    Section("Connection") {
                        LabeledContent("Type") {
                            HStack(spacing: 6) {
                                if client.usingBluetooth {
                                    Image("Bluetooth").resizable().scaledToFit().frame(width: 12, height: 20)
                                } else {
                                    Image(systemName: "wifi")
                                }
                                Text(client.usingBluetooth ? "Bluetooth" : "Wi-Fi")
                            }.foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Connection type")
                        .accessibilityValue(client.usingBluetooth ? "Bluetooth" : "Wi-Fi")
                        .accessibilityIdentifier("connection-type")
                    }.listRowBackground(tileColor)
                }
                Section {
                    HStack {
                        Text("Name")
                        Spacer(minLength: 20)
                        TextField("Name", text: $name).multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: "name").accessibilityIdentifier("settings-name")
                    }
                    Picker("Type", selection: $strip) { ForEach(["WS2805","WS2814","WS2812","SK6812"], id: \.self) { Text($0) } }.tint(.white).accessibilityIdentifier("settings-strip")
                    HStack {
                        Text("LED Count")
                        Spacer(minLength: 20)
                        TextField("1–1024", text: $count).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 100)
                            .focused($focusedField, equals: "count").accessibilityLabel("LED Count").accessibilityIdentifier("settings-count")
                    }
                    if !client.isSimulator {
                    HStack {
                        Text("Data Pin")
                        Spacer(minLength: 20)
                        TextField("0–54", text: $gpio).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 100)
                            .focused($focusedField, equals: "gpio").accessibilityLabel("Data Pin").accessibilityIdentifier("settings-gpio")
                    }
                    }
                } header: { Text("LED Strip") } footer: {
                    if !validCount { Text("LED Count must be between 1 and 1024.") }
                    else if !validGPIO { Text("Data Pin must be between 0 and 54.") }
                }.listRowBackground(tileColor).disabled(saving || installing)
                if !client.isSimulator {
                Section {
                    Toggle("Enable Relay", isOn: $relayEnabled).accessibilityIdentifier("settings-relay-enabled")
                        .disabled((client.state?.build ?? 0) < 27)
                    if relayEnabled {
                        HStack {
                            Text("Relay GPIO")
                            Spacer(minLength: 20)
                            TextField("0–54", text: $relayGPIO).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 100)
                                .focused($focusedField, equals: "relayGPIO").accessibilityLabel("Relay GPIO").accessibilityIdentifier("settings-relay-gpio")
                        }
                        Toggle("Invert Relay", isOn: $relayInverted).accessibilityIdentifier("settings-relay-inverted")
                        Text("Enable inversion for a relay that switches on when its GPIO is low.").font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text("Relay") } footer: {
                    Text("A relay switches power to your LED strip, reducing standby power when the light is off. Enable this if your controller uses a relay to power its LEDs.")
                    if !validRelayGPIO { Text("Relay GPIO must be between 0 and 54 and different from Data Pin.") }
                    if (client.state?.build ?? 0) < 27 { Text("Relay settings require firmware build 27 or newer.") }
                }.listRowBackground(tileColor).disabled(saving || installing)
                Section {
                    Toggle("Enable Wi-Fi", isOn: $wifiEnabled).accessibilityIdentifier("settings-wifi-enabled")
                        .disabled((client.state?.build ?? 0) < 34 || saving || installing)
                    if wifiEnabled {
                    let ip = client.state?.lanIP ?? ""
                    let connected = client.wifiStatus?.connected ?? (!ip.isEmpty && ip != "0.0.0.0")
                    let ssid = client.wifiStatus?.ssid ?? ""
                    let gateway = client.wifiStatus?.gateway ?? ""
                    let dns = client.wifiStatus?.dns.joined(separator: ", ") ?? ""
                    LabeledContent("SSID", value: connected ? (ssid.isEmpty ? "—" : ssid) : "Not connected")
                    LabeledContent("IP Address", value: connected && !ip.isEmpty && ip != "0.0.0.0" ? ip : "—")
                    LabeledContent("Gateway", value: connected && !gateway.isEmpty ? gateway : "—")
                    LabeledContent("DNS", value: connected && !dns.isEmpty ? dns : "—")
                    Button("Configure Wi-Fi") { configureWifi = true }.tint(accent).disabled(client.state?.wifiEnabled == false)
                    }
                } header: { Text("Wi-Fi") } footer: {
                    Text("Changing this setting restarts Luxio. When disabled, Wi-Fi and its network services release their memory. Re-enable it using Bluetooth or USB; the saved network is retained.")
                    if (client.state?.build ?? 0) < 34 { Text("Requires firmware build 34 or newer.") }
                }.listRowBackground(tileColor)
                .navigationDestination(isPresented: $configureWifi) { WifiSetupView(client: client) }
                Section("Firmware") {
                    LabeledContent("Build", value: String(client.state?.build ?? 0))
                    Button { Task {
                        checkingUpdate = true; availableBuild = 0
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
                            if availableBuild > 0 { showUpdate = true }
                            else { upToDate = true }
                            client.error = nil
                        } catch { client.report(error, action: "Check for updates") }
                    } } label: {
                        HStack {
                            if checkingUpdate { ProgressView().tint(.gray) }
                            Text(checkingUpdate ? "Checking..." : "Check for Updates")
                        }
                    }.disabled(checkingUpdate || installing || client.state == nil)
                    if availableBuild > 0 {
                        Button("Update Available") { showUpdate = true }.disabled(installing || checkingUpdate)
                    }

                }.listRowBackground(tileColor)
                .alert("Up to Date", isPresented: $upToDate) {
                    Button("OK", role: .cancel) {}
                } message: { Text("Your Luxio is running the latest firmware.") }
                if client.state?.supportsMatter != false {
                Section {
                    Toggle("Enable Matter", isOn: $matterEnabled).accessibilityIdentifier("settings-matter-enabled")
                        .disabled((client.state?.build ?? 0) < 34 || saving || installing)
                    if matterEnabled && wifiEnabled && client.state?.matterEnabled != false {
                    Button { Task { do { let response = try await client.request(12); pairing = response.text(6); qr = response.text(7); client.error = nil } catch { client.report(error, action: "Show Pairing Code") } } } label: {
                        Label("Show Pairing Code", systemImage: "matter.logo")
                    }.tint(accent)
                    if !pairing.isEmpty {
                        VStack(spacing: 16) {
                            if !qr.isEmpty {
                                let filter = CIFilter.qrCodeGenerator()
                                let _ = filter.setValue(Data(qr.utf8), forKey: "inputMessage")
                                if let image = filter.outputImage, let cg = CIContext().createCGImage(image.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), from: image.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) {
                                    Image(uiImage: UIImage(cgImage: cg)).interpolation(.none).resizable().scaledToFit().frame(width: 180).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
                                        .accessibilityLabel("Matter Pairing QR Code")
                                }
                            }
                            HStack(spacing: 8) {
                                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                                Text(pairing).font(.title2.monospaced()).lineLimit(1).minimumScaleFactor(0.6).textSelection(.enabled)
                                    .accessibilityIdentifier("pairing-code")
                                Button {
                                    UIPasteboard.general.string = pairing; copiedPairing = true
                                } label: {
                                    Image(systemName: copiedPairing ? "checkmark" : "doc.on.doc").frame(width: 44, height: 44)
                                }.buttonStyle(.plain).tint(.white).accessibilityLabel(copiedPairing ? "Pairing Code Copied" : "Copy Pairing Code")
                                    .accessibilityIdentifier("copy-pairing-code")
                            }
                        }.frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    }
                } header: { Text("Matter") } footer: {
                    Text("Matter connects Luxio to compatible smart home systems. It starts only when Wi-Fi is connected. Changing this setting restarts Luxio to release its memory; existing pairings are retained.")
                    if (client.state?.build ?? 0) < 34 { Text("Requires firmware build 34 or newer.") }
                }.listRowBackground(tileColor)
                }
                } else {
                    Section("Simulator") {
                        Text("A virtual Luxio device running on this iPhone.").font(.footnote).foregroundStyle(.secondary)
                        Button("Remove Simulator", role: .destructive) { dismiss(); removeSimulator?() }
                    }.listRowBackground(tileColor)
                }

            }.scrollContentBackground(.hidden).background(backdrop).navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            guard let ledCount = Int(count), (1...1024).contains(ledCount), let pin = Int(gpio), (0...54).contains(pin), validRelayGPIO else { return }
                            focusedField = nil
                            if !wifiEnabled && client.state?.wifiEnabled == true && !client.usingBluetooth && !client.isSimulator {
                                confirmDisableWifi = true
                            } else { saving = true }
                        } label: {
                            if saving {
                                ProgressView().controlSize(.small).frame(width: 20, height: 20)
                            } else {
                                Text("Save")
                            }
                        }.accessibilityLabel(saving ? "Saving" : "Save")
                            .tint(.white).disabled(saving || installing || client.state == nil || trimmedName.isEmpty || trimmedName.utf8.count > 63 || !validCount || !validGPIO || !validRelayGPIO)
                    }
                }
                .task(id: saving) {
                    guard saving, let ledCount = Int(count), let pin = Int(gpio) else { return }
                    defer { saving = false }
                    do {
                        var config = Proto(); config.string(1, trimmedName); config.string(2, strip); config.uint(3, UInt64(ledCount)); config.uint(4, UInt64(pin)); config.uint(5, UInt64(client.state?.channel ?? 0))
                        if !client.isSimulator && (client.state?.build ?? 0) >= 27 {
                            var relay = Proto(); relay.uint(1, relayEnabled ? 1 : 0); relay.uint(2, relayEnabled ? UInt64(Int(relayGPIO)!) : 0); relay.uint(3, relayInverted ? 1 : 0)
                            config.data(6, relay.bytes)
                        }
                        if !client.isSimulator && (client.state?.build ?? 0) >= 34 {
                            var wifi = Proto(); wifi.uint(1, wifiEnabled ? 1 : 0); config.data(7, wifi.bytes)
                            var matter = Proto(); matter.uint(1, matterEnabled ? 1 : 0); config.data(8, matter.bytes)
                        }
                        var payload = Proto(); payload.data(5, config.bytes)
                        _ = try await client.request(3, payload: payload); client.error = nil; dismiss()
                    } catch { client.report(error, action: "Save settings") }
                }
                .alert("Disable Wi-Fi?", isPresented: $confirmDisableWifi) {
                    Button("Disable Wi-Fi", role: .destructive) { saving = true }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You are connected over Wi-Fi. Saving will restart Luxio and disconnect this connection and Matter. You will need Bluetooth or USB to enable Wi-Fi again.")
                }
                .interactiveDismissDisabled(saving || installing)
                .task(id: copiedPairing) {
                    guard copiedPairing else { return }
                    try? await Task.sleep(for: .seconds(2))
                    copiedPairing = false
                }
        }.modifier(ActionToast(failure: $client.failure)).sheet(isPresented: $showUpdate, onDismiss: {
            if (client.state?.build ?? 0) >= availableBuild { availableBuild = 0 }
        }) {
            FirmwareUpdateView(client: client, build: availableBuild, installing: $installing)
        }.task {
            await client.refresh()
            if let state = client.state { name = state.name; strip = state.strip; count = String(state.count); gpio = String(state.gpio); relayEnabled = state.relayEnabled; relayGPIO = String(state.relayGPIO); relayInverted = state.relayInverted; wifiEnabled = state.wifiEnabled; matterEnabled = state.matterEnabled }
        }
    }
}


struct AnimationParameterControls: View {
    @ObservedObject var client: LightClient
    let title: String
    let scriptId: String
    let scriptName: String
    @Environment(\.dismiss) private var dismiss
    @State private var parameters: [AnimationParameter] = []
    @State private var busy = false
    @State private var editing = false
    @State private var error: String?
    @State private var numberDrafts: [String: String] = [:]
    @FocusState private var focusedNumber: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach($parameters) { $parameter in
                        if parameter.boolean {
                            Toggle(parameter.name, isOn: Binding(get: { parameter.value != 0 }, set: { value in
                                parameter.value = value ? 1 : 0
                                Task { _ = await apply([parameter]) }
                            }))
                        } else if parameter.minimum.isFinite && parameter.maximum.isFinite && parameter.minimum < parameter.maximum {
                            if parameter.numberInput {
                                HStack {
                                    Text(parameter.name)
                                    Spacer()
                                    TextField(parameter.name, text: Binding(get: { numberDrafts[parameter.name] ?? String(parameter.value) }, set: { numberDrafts[parameter.name] = $0 }))
                                        .multilineTextAlignment(.trailing).frame(width: 110).textFieldStyle(.roundedBorder)
                                        .keyboardType(.numbersAndPunctuation).submitLabel(.done).focused($focusedNumber, equals: parameter.name)
                                        .onSubmit {
                                            let text = numberDrafts[parameter.name] ?? String(parameter.value)
                                            guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite, value >= parameter.minimum, value <= parameter.maximum else {
                                                error = "\(parameter.name) must be between \(parameter.minimum) and \(parameter.maximum)."; return
                                            }
                                            parameter.value = value; numberDrafts.removeValue(forKey: parameter.name); focusedNumber = nil
                                            Task { _ = await apply([parameter]) }
                                        }
                                }
                            } else {
                                VStack(spacing: 8) {
                                    HStack { Text(parameter.name); Spacer(); Text(parameter.value, format: .number.precision(.fractionLength(0...2))).foregroundStyle(.secondary).monospacedDigit() }
                                    Slider(value: $parameter.value, in: parameter.minimum...parameter.maximum, onEditingChanged: { active in
                                        editing = active
                                        if !active { Task { _ = await apply([parameter]) } }
                                    }).accessibilityLabel(parameter.name)
                                }
                            }
                        }
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    Button("Reset to Defaults") { Task {
                        focusedNumber = nil; numberDrafts = [:]
                        let defaults = parameters.map { parameter in var value = parameter; value.value = value.defaultValue; return value }
                        _ = await apply(defaults)
                    } }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                    Text("Settings are saved on this device for this Luxio and animation.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24).disabled(busy)
            }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            var values = parameters
                            for index in values.indices where values[index].numberInput {
                                guard let draft = numberDrafts[values[index].name] else { continue }
                                guard let value = Double(draft.replacingOccurrences(of: ",", with: ".")), value.isFinite,
                                      value >= values[index].minimum, value <= values[index].maximum else {
                                    error = "\(values[index].name) must be between \(values[index].minimum) and \(values[index].maximum)."; return
                                }
                                values[index].value = value
                            }
                            focusedNumber = nil
                            Task { if numberDrafts.isEmpty { dismiss() } else if await apply(values) { dismiss() } }
                        }.disabled(busy).accessibilityIdentifier("animation-settings-done")
                    }
                }
        }.tint(Color(red: 0, green: 210 / 255, blue: 1))
            .interactiveDismissDisabled(busy || !numberDrafts.isEmpty)
            .modifier(ActionToast(failure: $client.failure))
            .onAppear { parameters = client.state?.parameters ?? [] }
            .onChange(of: client.state?.parameters) { _, values in if !editing && focusedNumber == nil && !busy { parameters = values ?? [] } }
            .onChange(of: "\(client.state?.mode ?? 0)-\(client.state?.activeScript ?? "")-\(client.state?.scriptName ?? "")") { _, _ in
                if client.state?.mode != 2 || client.state?.activeScript != scriptId || client.state?.scriptName != scriptName { dismiss() }
            }
    }
    private func apply(_ values: [AnimationParameter]) async -> Bool {
        guard !busy, let state = client.state, state.mode == 2, state.activeScript == scriptId, state.scriptName == scriptName else { return false }
        busy = true; error = nil; defer { busy = false }
        do {
            var payload = Proto()
            if !scriptId.isEmpty { payload.string(8, scriptId) }
            else { var animation = Proto(); animation.string(2, scriptName); payload.data(7, animation.bytes) }
            for parameter in values { payload.data(17, parameter.proto.bytes) }
            _ = try await client.request(32, payload: payload)
            guard let updated = client.state, updated.mode == 2, updated.activeScript == scriptId, updated.scriptName == scriptName else { dismiss(); return false }
            parameters = updated.parameters
            var stored = Proto(); for parameter in parameters { stored.data(17, parameter.proto.bytes) }
            let key = scriptId.isEmpty ? "preset.\(scriptName)" : "saved.\(scriptId)"
            UserDefaults.standard.set(stored.bytes, forKey: "luxio.animation-settings.\(state.deviceId).\(key)")
            return true
        } catch {
            client.report(error, action: "Change animation settings"); parameters = client.state?.parameters ?? []
            return false
        }
    }
}
