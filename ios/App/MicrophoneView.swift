import Combine
import RouteCore
import SwiftUI

struct MicrophoneView: View {
    @ObservedObject var session: MicrophoneSession
    @Environment(\.scenePhase) private var scenePhase
    private let clock = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    private let orange = Color(red: 0.93, green: 0.26, blue: 0.10)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Text("clearmic").font(.system(size: 24, weight: .medium, design: .rounded))
                    Spacer()
                    ShareLink(item: session.diagnostics + "\niOS " + UIDevice.current.systemVersion) {
                        Image(systemName: "square.and.arrow.up")
                    }.accessibilityLabel("Share route diagnostics")
                }
                Text("BLUETOOTH / CAMERA ROUTE TEST").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your microphone. Your Camera.").font(.title2.weight(.medium))
                    Text("Pair your DJI or other Bluetooth microphone in iPhone Settings → Bluetooth. Then select it here and check your voice before switching to Camera.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button {
                    Task { await session.discover() }
                } label: {
                    Label(session.state == .preparing ? "Checking microphones…" : session.selectedID.isEmpty ? "Find microphones" : "Reconnect & recheck", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(InstrumentButton(active: true)).disabled(session.state == .preparing)
                Text("Microphone access is requested when you connect. A level test records up to 30 seconds temporarily, then deletes it. ClearMic does not play your mic through the speaker.")
                    .font(.caption).foregroundStyle(.secondary)
                if !session.inputs.isEmpty {
                    section("01 / INPUT") {
                        ForEach(session.inputs.sorted { $0.bluetooth && !$1.bluetooth }) { input in
                            Button {
                                Task { await session.select(input.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: input.bluetooth ? "antenna.radiowaves.left.and.right" : "mic")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(input.name).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
                                        Text(input.bluetooth ? "Bluetooth input" : "Other input").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: session.selectedID == input.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(session.selectedID == input.id ? orange : .secondary)
                                }
                            }.buttonStyle(InstrumentButton()).disabled(session.state == .preparing)
                        }
                        if !session.inputs.contains(where: \.bluetooth) {
                            Text("No Bluetooth microphone is exposed to iOS audio yet. Check pairing, then refresh. A device that only supports Bluetooth playback cannot act as a microphone.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                section("02 / LEVEL CHECK") {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text(session.state.title).font(.system(size: 12, weight: .medium, design: .monospaced))
                            Spacer()
                            if session.state == .testing { Circle().fill(orange).frame(width: 7, height: 7) }
                        }
                        Text(session.verifiedInput.map { "Last verified in ClearMic: \($0.name)" } ?? "No input verified")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            ForEach(0..<24, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 1).fill(session.state == .testing && session.peakDB > -60 + Float(index) * 2.5 ? orange : Color.primary.opacity(0.10))
                                    .frame(height: 18)
                            }
                        }.accessibilityLabel("Microphone peak").accessibilityValue(session.state == .testing ? "\(Int(session.peakDB)) decibels" : "Test stopped")
                        Text(session.state == .testing ? String(format: "%.1f dBFS", session.peakDB) : "Speak during the level test")
                            .font(.system(size: 12, design: .monospaced))
                        Button(session.state == .testing ? "Stop level test" : "Test microphone") {
                            if session.state == .testing { session.stopTest() } else { session.startTest() }
                        }.buttonStyle(InstrumentButton(active: session.state == .testing))
                            .disabled(!session.canTest && session.state != .testing)
                        if let gain = session.inputGain {
                            VStack(alignment: .leading) {
                                Text("Microphone gain · \(Int(gain * 100))%").font(.caption)
                                Slider(value: Binding(get: { Double(session.inputGain ?? 0) }, set: { session.setGain(Float($0)) }), in: 0...1)
                                    .tint(orange).accessibilityLabel("Microphone hardware gain")
                                    .disabled(session.state != .ready && session.state != .testing)
                            }
                        }
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                }
                section("03 / TRY APPLE CAMERA") {
                    Button { session.prepareCamera() } label: {
                        Label("Prepare Camera", systemImage: "camera").frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(InstrumentButton(active: session.canHandoff)).disabled(!session.canHandoff)
                    if session.state == .cameraHandoff {
                        Text("Switch to Apple's Camera app and record a short video. Speak into the Bluetooth mic while the iPhone is farther away, then play the video back to check which microphone it used.")
                            .font(.subheadline)
                        Text("ClearMic's test is stopped. The audio session remains prepared until iOS takes control. Return here and reconnect to test again.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Stops the level test and leaves the selected audio session prepared. You then switch to Camera yourself.").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Experimental: iOS may choose a different input in Camera. This app cannot confirm or force Camera's microphone, or send ClearMic EQ into its recording.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if case .failed(let reason) = session.state {
                    Text(reason).font(.subheadline).foregroundStyle(orange)
                    Button("App permissions") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.buttonStyle(InstrumentButton())
                } else if session.state == .sourceLost || session.state == .interrupted {
                    Text("Reconnect your selected mic, then tap Reconnect & recheck. ClearMic won't substitute the iPhone microphone automatically.")
                        .font(.subheadline).foregroundStyle(orange)
                }
                HStack {
                    Text("LOCAL AUDIO / ROUTE PROTOTYPE").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Stop", systemImage: "power") { session.stop() }.buttonStyle(InstrumentButton())
                }
            }.padding(22).frame(maxWidth: 700, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(uiColor: .systemBackground))
        .tint(orange)
        .onReceive(clock) { _ in session.poll() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { session.returnedToForeground() } }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InstrumentButton: ButtonStyle {
    var active = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 16).padding(.vertical, 14)
            .foregroundStyle(active ? Color.white : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 10).fill(active ? Color(red: 0.82, green: 0.19, blue: 0.055) : Color(uiColor: .secondarySystemBackground))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(scheme == .dark ? 0.15 : 0.08)))
                    .shadow(color: .black.opacity(configuration.isPressed ? 0.05 : 0.13), radius: 3, x: 1, y: 3)
            }
            .offset(y: configuration.isPressed ? 1 : 0)
            .opacity(enabled ? 1 : 0.45)
    }
}
