import SwiftUI

@MainActor final class ColorEditor: ObservableObject {
    @Published var points: [GradientPoint]
    @Published var selected: UUID
    @Published var loading = true
    @Published var loadFailed = false
    @Published var sending = false
    @Published var dragging = false
    @Published var error: String?
    private var queued: [GradientPoint]?
    let client: LightClient
    var strip: String { client.state?.strip ?? "WS2805" }
    init(client: LightClient) {
        self.client = client
        let point = GradientPoint(channels: client.state?.channels ?? [255, 0, 0, 0, 0, 0])
        points = [point]; selected = point.id
    }
    func load(mode: LightMode) async {
        loading = true; loadFailed = false; error = nil
        defer { loading = false }
        if mode == .gradient, let fields = client.state?.gradient, let gradient = CustomGradient(fields: fields, strip: strip) {
            points = gradient.points
        } else if mode == .color {
            points = [GradientPoint(channels: client.state?.channels ?? [255, 0, 0, 0, 0, 0])]
        }
        if mode == .gradient && points.count == 1 {
            points.append(GradientPoint(hue: (points[0].hue + 1.0 / 6).truncatingRemainder(dividingBy: 1), saturation: 0.9, white: points[0].white, temperature: points[0].temperature < 0.5 ? 1 : 0))
        }
        if !points.contains(where: { $0.id == selected }) { selected = points[0].id }
    }
    // Coalesce edits while a request is in flight. Never cancel an upload halfway
    // through; send the newest complete gradient next, so older edits cannot win.
    func apply() {
        guard !loading && !loadFailed else { return }
        queued = points
        guard !sending else { return }
        sending = true
        Task {
            defer { sending = false }
            while let snapshot = queued {
                queued = nil
                do {
                    if snapshot.count == 1 {
                        var color = Proto()
                        for (i, value) in snapshot[0].channels(strip: strip).enumerated() { color.uint(i + 1, UInt64(value)) }
                        var payload = Proto(); payload.data(3, color.bytes)
                        _ = try await client.request(1, payload: payload)
                    } else {
                        var payload = Proto(); payload.data(11, try CustomGradient(points: snapshot).proto(strip: strip).bytes)
                        _ = try await client.request(17, payload: payload)
                    }
                    error = nil; client.error = nil
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}

extension GradientPoint {
    var preview: Color {
        white ? Color(red: (255 - 55 * temperature) / 255, green: (190 + 40 * temperature) / 255, blue: (100 + 155 * temperature) / 255) : Color(hue: hue, saturation: saturation, brightness: 1)
    }
}

struct ColorControls: View {
    @ObservedObject var client: LightClient
    @ObservedObject var editor: ColorEditor
    let mode: LightMode
    @Binding var isSending: Bool
    var body: some View {
        let selected = editor.points.firstIndex { $0.id == editor.selected } ?? 0
        let white = editor.points[selected].white
        let colors = editor.points.map { $0.white && (editor.strip == "WS2814" || editor.strip == "SK6812") ? Color.white : $0.preview }
        VStack(spacing: 22) {
                ColorWheel(editor: editor).frame(maxWidth: 420).padding(.horizontal, 22).disabled(editor.loading || editor.loadFailed || client.state == nil)
                if client.state?.supportsWhite == true || client.state?.supportsWhiteTemperature == true {
                    HStack {
                        HStack(spacing: 6) {
                            Button {
                                editor.points[selected].originalChannels = nil; editor.points[selected].white = false; editor.apply()
                            } label: {
                                Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center)).frame(width: 28, height: 28)
                                    .padding(6).overlay { Circle().strokeBorder(white ? .clear : .white, lineWidth: 2) }
                            }.accessibilityLabel("Color wheel").accessibilityAddTraits(!white ? .isSelected : [])
                            if editor.strip == "WS2805" || (editor.strip == "WS2814" || editor.strip == "SK6812") {
                                Button {
                                    editor.points[selected].originalChannels = nil; editor.points[selected].white = true; editor.apply()
                                } label: {
                                    Circle().fill(LinearGradient(colors: (editor.strip == "WS2814" || editor.strip == "SK6812") ? [.white, .white] : [Color(red: 1, green: 0.73, blue: 0.3), .white, .cyan.opacity(0.6)], startPoint: .top, endPoint: .bottom)).frame(width: 28, height: 28)
                                        .padding(6).overlay { Circle().strokeBorder(white ? .white : .clear, lineWidth: 2) }
                                }.accessibilityLabel(editor.strip == "WS2805" ? "White temperature wheel" : "White channel").accessibilityAddTraits(white ? .isSelected : [])
                            }
                        }.padding(5).background(.white.opacity(0.1), in: Capsule())
                        Spacer()

                    }.padding(.horizontal, 22).disabled(editor.loading || editor.loadFailed || client.state == nil)
                }
                if mode == .gradient {
                VStack(spacing: 12) {
                    LinearGradient(colors: colors.count == 1 ? colors + colors : colors, startPoint: .leading, endPoint: .trailing)
                        .frame(height: 14).clipShape(Capsule()).padding(.horizontal, 24).accessibilityLabel("Strip gradient preview, \(editor.points.count) colors")
                    HStack {
                        Text("START"); Spacer(); Text("END")
                    }.font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(.white.opacity(0.4)).padding(.horizontal, 24)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(editor.points.enumerated()), id: \.element.id) { index, point in
                                Button { editor.selected = point.id } label: {
                                    Circle().fill(point.white && (editor.strip == "WS2814" || editor.strip == "SK6812") ? Color.white : point.preview).frame(width: 36, height: 36)
                                        .overlay { Text("\(index + 1)").font(.system(size: 13, weight: .bold)).foregroundStyle(.black.opacity(0.7)) }
                                        .padding(4).overlay { Circle().strokeBorder(point.id == editor.selected ? .white : .clear, lineWidth: 2) }
                                }.accessibilityLabel("Select point \(index + 1)").accessibilityAddTraits(point.id == editor.selected ? .isSelected : [])
                            }
                            Button {
                                let point = GradientPoint(hue: (editor.points[selected].hue + 1.0 / 6).truncatingRemainder(dividingBy: 1), saturation: 0.9, white: white, temperature: (editor.points[selected].temperature + 0.3).truncatingRemainder(dividingBy: 1))
                                editor.points.append(point); editor.selected = point.id; editor.apply()
                            } label: {
                                Image(systemName: "plus").font(.system(size: 19, weight: .medium))
                                    .frame(width: 44, height: 44).background(.white.opacity(0.12), in: Circle())
                            }.disabled(editor.points.count >= 8).accessibilityLabel("Add point")
                                .accessibilityHint("Adds a color at the end of the strip gradient. Up to eight points.")
                            Button {
                                editor.points.remove(at: selected)
                                editor.selected = editor.points[min(selected, editor.points.count - 1)].id
                                editor.apply()
                            } label: {
                                Image(systemName: "minus").font(.system(size: 19, weight: .medium))
                                    .frame(width: 44, height: 44).background(.white.opacity(0.12), in: Circle())
                            }.disabled(editor.points.count <= 2).accessibilityLabel("Remove point \(selected + 1)")
                        }.padding(.horizontal, 24).padding(.vertical, 2)
                    }

                }.disabled(editor.loading || editor.loadFailed || client.state == nil)
                }
                if let error = editor.error {
                    VStack(spacing: 8) {
                        Text(error).font(.footnote).foregroundStyle(.red)
                        Button("Retry") { if editor.loadFailed { Task { await editor.load(mode: mode) } } else { editor.apply() } }.disabled(editor.sending)
                    }.padding(.horizontal, 24)
                }
        }.padding(.bottom, 8).frame(maxWidth: 500).frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .task(id: "\(client.state?.activeGradient ?? "")-\(client.state?.activeColor ?? "")") { if !editor.sending && !editor.dragging { await editor.load(mode: mode) } }
            .onChange(of: editor.sending) { _, value in isSending = value }
            .onDisappear { isSending = false }
            .onChange(of: client.state?.gradient) { _, _ in
                if mode == .gradient, !editor.sending, !editor.dragging, !editor.loading { Task { await editor.load(mode: mode) } }
            }
            .onChange(of: client.state?.channels) { _, channels in
                if mode == .color, !editor.sending, !editor.dragging, !editor.loading, let channels {
                    let point = GradientPoint(channels: channels)
                    editor.points = [point]; editor.selected = point.id
                }
            }

    }
}

private struct ColorWheel: View {
    @ObservedObject var editor: ColorEditor
    var body: some View {
        let selected = editor.points.firstIndex { $0.id == editor.selected } ?? 0
        let white = editor.points[selected].white
        GeometryReader { geometry in
            let radius = geometry.size.width / 2
            ZStack {
                if white {
                    Circle().fill(LinearGradient(colors: (editor.strip == "WS2814" || editor.strip == "SK6812") ? [.white, .white] : [Color(red: 1, green: 0.73, blue: 0.3), Color(red: 1, green: 0.93, blue: 0.65), .white, Color(red: 0.78, green: 0.93, blue: 1)], startPoint: .top, endPoint: .bottom))
                } else {
                    Circle().fill(AngularGradient(gradient: Gradient(colors: (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: 1) }), center: .center, startAngle: .degrees(-120), endAngle: .degrees(240)))
                        .overlay { Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius)) }
                }
            }.shadow(color: .black.opacity(0.35), radius: 16, y: 8)
                .contentShape(Circle())
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("wheel"))
                    .onChanged { value in guard !white || editor.strip == "WS2805" else { return }; editor.dragging = true; editor.points[selected].move(x: (value.location.x - radius) / radius, y: (value.location.y - radius) / radius) }
                    .onEnded { _ in editor.dragging = false; editor.apply() })
            ForEach(Array(editor.points.enumerated()), id: \.element.id) { index, point in
                if point.white == white {
                    let y = white ? (editor.strip == "WS2805" ? point.temperature * 2 - 1 : 0) : sin(point.hue * 2 * .pi - 2 * .pi / 3) * point.saturation
                    let limit = sqrt(max(0, 1 - y * y))
                    let x = white ? min(max(point.whiteX ?? 0, -limit), limit) : cos(point.hue * 2 * .pi - 2 * .pi / 3) * point.saturation
                    Circle().fill(point.white && (editor.strip == "WS2814" || editor.strip == "SK6812") ? Color.white : point.preview).frame(width: point.id == editor.selected ? 34 : 28, height: point.id == editor.selected ? 34 : 28)
                        .overlay { Circle().strokeBorder(.white, lineWidth: 3) }
                        .overlay { Text("\(index + 1)").font(.system(size: 12, weight: .bold)).foregroundStyle(.black.opacity(0.7)) }
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
                        .frame(width: 44, height: 44).contentShape(Circle())
                        .position(x: radius + x * radius, y: radius + y * radius)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("wheel"))
                            .onChanged { value in
                                guard !point.white || editor.strip == "WS2805" else { editor.selected = point.id; return }
                                editor.dragging = true; editor.selected = point.id
                                editor.points[index].move(x: (value.location.x - radius) / radius, y: (value.location.y - radius) / radius)
                            }.onEnded { _ in editor.dragging = false; editor.apply() })
                        .accessibilityElement(children: .ignore).accessibilityLabel("Color point \(index + 1)")
                        .accessibilityValue(point.white ? (editor.strip == "WS2805" ? "White temperature \(Int(point.temperature * 100)) percent" : "White channel") : "Hue \(Int(point.hue * 360)) degrees, saturation \(Int(point.saturation * 100)) percent")
                        .accessibilityAdjustableAction { direction in
                            guard !point.white || editor.strip == "WS2805" else { return }
                            editor.selected = point.id; editor.points[index].originalChannels = nil
                            let delta = direction == .increment ? 0.05 : -0.05
                            if point.white { editor.points[index].temperature = min(max(point.temperature + delta, 0), 1) }
                            else { editor.points[index].hue = (point.hue + delta + 1).truncatingRemainder(dividingBy: 1) }
                            editor.apply()
                        }
                }
            }
        }.coordinateSpace(name: "wheel").aspectRatio(1, contentMode: .fit).padding(.vertical, 18)
    }
}
