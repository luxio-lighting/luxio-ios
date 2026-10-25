import SwiftUI

struct WifiSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var client: LightClient
    @State private var networks: [WifiNetwork] = []
    @State private var choosingNetwork = true
    @State private var manual = false
    @State private var ssid = ""
    @State private var password = ""
    @State private var passwordRequired = true
    @State private var showPassword = false
    @State private var action = "scan"
    @State private var connected = false
    @State private var error: String?
    @FocusState private var passwordFocused: Bool
    private var valid: Bool { !ssid.isEmpty && ssid.utf8.count <= 32 && (!passwordRequired || (8...63).contains(password.utf8.count) || (password.utf8.count == 64 && password.allSatisfy { $0.isHexDigit })) }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: connected ? "checkmark.circle.fill" : "wifi")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(connected ? Color.green : Color.accentColor)
                        .accessibilityHidden(true)
                    VStack(spacing: 8) {
                        Text(connected ? "You're connected" : action == "connect" ? "Connecting to Wi-Fi" : choosingNetwork ? "Choose a network" : "Join your network")
                            .font(.title2.bold())
                        Text(connected ? "Luxio is now connected to \(ssid)." : action == "connect" ? "Joining \(ssid)…\nKeep Luxio powered on and stay nearby." : choosingNetwork ? "Choose the Wi-Fi network you want Luxio to use." : passwordRequired ? "Enter the Wi-Fi password for \(manual && ssid.isEmpty ? "your network" : ssid)." : "This network doesn't require a password.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if action == "connect" { ProgressView().padding(.top, 8).accessibilityLabel("Connecting Luxio") }
                }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 20)
            }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))

            if !connected && action != "connect" {
                if choosingNetwork {
                    Section {
                        if action == "scan" {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Finding nearby networks…").foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        } else if networks.isEmpty && error == nil {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("No networks found").font(.subheadline.weight(.semibold))
                                Text("Try scanning again, move Luxio closer to your router, or enter a network manually.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                        ForEach(networks) { network in
                            Button {
                                if ssid != network.ssid || passwordRequired != network.passwordRequired { password = "" }
                                ssid = network.ssid; passwordRequired = network.passwordRequired
                                manual = false; choosingNetwork = false; showPassword = false; error = nil; action = ""
                            } label: {
                                HStack(spacing: 12) {
                                    Text(network.ssid).foregroundStyle(.primary)
                                    Spacer(minLength: 8)
                                    if network.passwordRequired { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                                    Image(systemName: "wifi", variableValue: network.rssi >= -55 ? 1 : network.rssi >= -70 ? 0.6 : 0.2)
                                        .foregroundStyle(.secondary)
                                }.padding(.vertical, 6).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel(network.ssid)
                                .accessibilityValue("\(network.passwordRequired ? "Secured" : "Open"), \(network.rssi >= -55 ? "strong" : network.rssi >= -70 ? "fair" : "weak") signal")
                        }
                    } header: { Text("Nearby networks") }
                    Section {
                        Button {
                            action = ""; choosingNetwork = false; manual = true
                            ssid = ""; password = ""; passwordRequired = true; showPassword = false; error = nil
                        } label: {
                            HStack {
                                Text("Other Network…")
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            }
                        }.accessibilityIdentifier("wifi-other")
                    } footer: { Text("For hidden networks, enter the name manually.") }
                } else {
                    Section("Network") {
                        if manual {
                            TextField("Network name", text: $ssid).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .accessibilityIdentifier("wifi-ssid")
                            Picker("Security", selection: $passwordRequired) {
                                Text("Password").tag(true)
                                Text("Open network").tag(false)
                            }.onChange(of: passwordRequired) { _, _ in password = ""; showPassword = false }
                        } else {
                            Label(ssid, systemImage: "wifi")
                        }
                        Button("Choose Another Network") { passwordFocused = false; choosingNetwork = true; error = nil }
                    }
                    if passwordRequired {
                        Section {
                            HStack {
                                Group {
                                    if showPassword { TextField("Password", text: $password) }
                                    else { SecureField("Password", text: $password) }
                                }.textContentType(.password).textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .focused($passwordFocused).submitLabel(.join)
                                    .onSubmit { if valid { passwordFocused = false; action = "connect" } }
                                    .accessibilityIdentifier("wifi-password")
                                Button {
                                    showPassword.toggle(); passwordFocused = true
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye").foregroundStyle(.secondary)
                                }.buttonStyle(.plain).accessibilityLabel(showPassword ? "Hide password" : "Show password")
                            }
                        } header: { Text("Password") } footer: {
                            if !password.isEmpty && !valid && ssid.utf8.count <= 32 { Text("Use 8–63 characters, or a 64-digit hexadecimal key.") }
                        }
                    }
                    if ssid.utf8.count > 32 { Text("The network name must be 32 bytes or fewer.").font(.footnote).foregroundStyle(.red) }
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.red)
                    }
                }
            }
        }
        .tint(Color.accentColor)
        .navigationTitle("Wi-Fi").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: password) { _, _ in error = nil }
        .onChange(of: ssid) { _, _ in error = nil }
        .toolbar {
            if choosingNetwork && !connected {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { error = nil; action = "scan" } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(action == "scan").accessibilityLabel("Scan Again")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if connected || (!choosingNetwork && action != "connect") {
                Button {
                    if connected { dismiss() }
                    else { passwordFocused = false; action = "connect" }
                } label: {
                    Text(connected ? "Done" : "Connect to Wi-Fi").fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!connected && !valid).accessibilityIdentifier(connected ? "wifi-done" : "wifi-connect")
                    .padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
            }
        }
        .task(id: action) {
            guard !action.isEmpty else { return }
            let operation = action
            error = nil
            do {
                if operation == "scan" {
                    var result = try await client.request(16)
                    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
                    while result.number(13) != 0 && ContinuousClock.now < deadline {
                        try await Task.sleep(for: .seconds(1))
                        do { result = try await client.request(0, timeout: 5) }
                        catch { try Task.checkCancellation() } // Wi-Fi may pause while the radio scans.
                    }
                    guard result.number(13) == 0 else { throw LuxioError.message("The scan timed out. Try again, or enter your network manually.") }
                    guard result.text(14).isEmpty else { throw LuxioError.message("Couldn't find networks. Try again, or enter your network manually.") }
                    networks = try (result[12] ?? []).map { try WifiNetwork(Proto.decode($0)) }.sorted { $0.rssi > $1.rssi }
                } else {
                    var wifi = Proto(); wifi.string(1, ssid); wifi.string(2, passwordRequired ? password : "")
                    var payload = Proto(); payload.data(6, wifi.bytes)
                    _ = try await client.request(4, payload: payload)
                    let deadline = ContinuousClock.now.advanced(by: .seconds(60))
                    while !connected && ContinuousClock.now < deadline {
                        try await Task.sleep(for: .seconds(2))
                        do {
                            let result = try await client.request(0, timeout: 5)
                            let network = try result.message(21)
                            let ip = client.state?.lanIP ?? ""
                            if network.number(1) != 0 && !ip.isEmpty && ip != "0.0.0.0" { connected = true }
                        } catch { try Task.checkCancellation() }
                    }
                    guard connected else { throw LuxioError.message("Luxio couldn't connect. Check the password and make sure the network is in range, then try again.") }
                    password = ""; showPassword = false
                }
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
            if !Task.isCancelled { action = "" }
        }
    }
}
