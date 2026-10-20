import AppKit
import SwiftUI

enum Panel {
    static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    static let ink = adaptive(NSColor(white: 0.18, alpha: 1), NSColor(white: 0.90, alpha: 1))
    static let ivory = adaptive(NSColor(red: 0.89, green: 0.88, blue: 0.84, alpha: 1), NSColor(srgbRed: 0.045, green: 0.05, blue: 0.048, alpha: 1))
    static let surface = adaptive(NSColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1), NSColor(srgbRed: 0.075, green: 0.08, blue: 0.077, alpha: 1))
    static let highlight = adaptive(NSColor(white: 1, alpha: 0.8), NSColor(white: 1, alpha: 0.035))
    static let capTop = adaptive(NSColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1), NSColor(srgbRed: 0.15, green: 0.16, blue: 0.155, alpha: 1))
    static let capBottom = adaptive(NSColor(red: 0.89, green: 0.88, blue: 0.84, alpha: 1), NSColor(srgbRed: 0.095, green: 0.10, blue: 0.097, alpha: 1))
    static let rim = adaptive(NSColor(white: 1, alpha: 0.65), NSColor(white: 1, alpha: 0.10))
    static let well = adaptive(NSColor(white: 0.18, alpha: 0.18), NSColor(white: 0, alpha: 0.8))
    static let orange = Color(red: 0.93, green: 0.26, blue: 0.10)
    static let lcd = Color(red: 0.77, green: 0.80, blue: 0.70)
}

struct ContentView: View {
    @ObservedObject var session: Session
    @State private var savingPreset = false
    @State private var presetName = ""
    @State private var showingSetup = false
    var body: some View {
        GeometryReader { geometry in
            let narrow = geometry.size.width < 740
            let padding: CGFloat = geometry.size.width < 440 ? 16 : 28
            let columns = Array(repeating: GridItem(.flexible(minimum: 99), spacing: 12, alignment: .leading),
                                count: max(2, min(6, Int((geometry.size.width - padding * 2 + 12) / 124))))
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: geometry.size.width < 380 ? 8 : 12) {
                        key("bypass", "arrow.triangle.branch", on: session.settings.bypass, color: Panel.orange) { session.settings.bypass.toggle() }
                        key("mute", "mic.slash", on: session.settings.muted, color: Panel.orange) { session.settings.muted.toggle() }
                        key("listen", "headphones", on: session.listening, color: Panel.orange) { session.toggleMonitoring() }
                            .disabled(session.selectedMonitor == nil)
                        key(session.running ? "stop" : "start", session.running ? "stop.fill" : "play.fill", on: session.running, color: Panel.orange) {
                            if session.running { session.stop() } else { Task { await session.start() } }
                        }.disabled(!session.running && !session.canStart)
                    }
                    (narrow ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20)) : AnyLayout(HStackLayout(alignment: .top, spacing: 28))) {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader(session.sourceLost ? "01 / SOURCE LOST" : "01 / SOURCE")
                            HStack(spacing: 8) {
                                HardwareSelector("Microphone", value: session.selectedDevice?.name ?? (session.settings.sourceUID.isEmpty ? "Select microphone" : "Input disconnected"), selection: Binding(get: { session.settings.sourceUID }, set: session.selectSource)) {
                                    Text("Select microphone").tag("")
                                    if !session.settings.sourceUID.isEmpty && session.selectedDevice == nil {
                                        Text("Saved input disconnected").tag(session.settings.sourceUID)
                                    }
                                    ForEach(session.devices) { device in
                                        Text(device.sampleRate == 48000 ? device.name : "\(device.name) (\(Int(device.sampleRate / 1000)) kHz, unsupported)").tag(device.uid)
                                    }
                                }
                                HardwareSelector("Input channel", value: session.settings.channel == -1 ? "both" : "\(session.settings.channel + 1)", selection: $session.settings.channel, compact: true) {
                                    ForEach(0..<max(1, session.selectedDevice?.inputChannels ?? 1), id: \.self) { Text("Input \($0 + 1)").tag($0) }
                                    if (session.selectedDevice?.inputChannels ?? 0) >= 2 { Text("Both · 1 + 2").tag(-1) }
                                }.frame(width: session.settings.channel == -1 ? 76 : 58)
                                .help("Choose one input channel, or blend inputs 1 and 2")
                            }
                            if session.sourceLost {
                                Button("reconnect") { Task { await session.reconnectSource() } }
                                    .buttonStyle(HardwareButton()).disabled(session.starting)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader("02 / HEADPHONE OUTPUT")
                            HardwareSelector("Headphone output", value: session.selectedMonitor?.name ?? (session.settings.monitorUID.isEmpty ? "Select headphones" : "Output disconnected"), selection: $session.settings.monitorUID) {
                                Text("Select headphones").tag("")
                                if !session.settings.monitorUID.isEmpty && session.selectedMonitor == nil {
                                    Text("Saved output disconnected").tag(session.settings.monitorUID)
                                }
                                ForEach(session.outputs) { Text($0.name).tag($0.uid) }
                            }
                            HStack(spacing: 10) {
                                Image(systemName: "headphones").foregroundStyle(Panel.orange)
                                Text("level").font(.system(size: 11, design: .monospaced))
                                Slider(value: $session.settings.monitorGain, in: -48...0).frame(minWidth: 50, maxWidth: .infinity).tint(Panel.orange)
                                    .accessibilityLabel("Headphone listening level").help("Only changes how loudly you hear yourself, not the microphone sent to other apps")
                                Text(String(format: "%.0f dB", session.settings.monitorGain)).font(.system(size: 11, design: .monospaced)).frame(width: 45, alignment: .trailing)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    display(narrow: narrow)
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader("03 / LEVEL & DYNAMICS", toggle: $session.settings.compression, toggleLabel: "Dynamics")
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                            dial("trim", "INPUT GAIN", $session.settings.inputGain, -12...18, "dB", Panel.ink)
                            dial("threshold", "COMPRESSOR", $session.settings.threshold, -40...0, "dB", Panel.ink)
                            dial("ratio", "COMPRESSION", $session.settings.ratio, 1...8, ":1", Panel.ink)
                            dial("output", "OUTPUT GAIN", $session.settings.makeup, -12...18, "dB", Panel.orange)
                        }
                    }
                    Divider().overlay(Panel.ink.opacity(0.12))
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader("04 / VOICE EQ", toggle: $session.settings.noiseReduction, toggleLabel: "Denoise")
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                            dial("rumble", "HIGH-PASS", $session.settings.highPass, 0...180, "Hz", Panel.ink)
                            dial("bass", "120 Hz SHELF", $session.settings.bass, -12...12, "dB", Panel.orange)
                            dial("body", "280 Hz", $session.settings.mud, -12...6, "dB", Panel.orange)
                            dial("clarity", "3.5 kHz", $session.settings.presence, -6...9, "dB", Panel.orange)
                            dial("air", "8 kHz SHELF", $session.settings.air, -12...12, "dB", Panel.orange)
                        }
                    }
                    Divider().overlay(Panel.ink.opacity(0.12))
                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeader("05 / STUDIO FINISH", toggle: $session.settings.studioEnabled, toggleLabel: "Studio finish")
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                            dial("de-ess", "SIBILANCE", $session.settings.deEss, 0...100, "%", Panel.orange)
                            dial("room", "REVERB MIX", $session.settings.reverb, 0...25, "%", Panel.orange)
                        }.disabled(!session.settings.studioEnabled).opacity(session.settings.studioEnabled ? 1 : 0.45)
                    }
                    Divider().overlay(Panel.ink.opacity(0.12))
                    VStack(alignment: .leading, spacing: 16) {
                        caption("06 / VOICES")
                        VoiceButtonLayout(spacing: 12) {
                            Button("natural") { session.applyNatural() }.buttonStyle(HardwareButton())
                            Button("flat") { session.applyFlat() }.buttonStyle(HardwareButton())
                            ForEach(session.presets) { preset in
                                let confirming = session.pendingPresetID == preset.id
                                let dirty = session.selectedPresetID == preset.id && session.presetIsDirty
                                Button {
                                    session.choosePreset(preset.id)
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(confirming ? "save over \(preset.name)?" : preset.name).lineLimit(1).truncationMode(.middle)
                                        if dirty && !confirming { Circle().fill(Panel.orange).frame(width: 5, height: 5).accessibilityHidden(true) }
                                    }.frame(maxWidth: 240)
                                }.buttonStyle(HardwareButton(selected: confirming || (session.selectedPresetID == preset.id && !dirty), color: Panel.orange))
                                .help(confirming ? "Click again to replace this saved voice with your current settings" : dirty ? "Changed. Click to choose this voice as the save target, then click again to confirm" : "Load saved voice")
                                .accessibilityValue(confirming ? "Confirm overwrite" : dirty ? "Modified" : session.selectedPresetID == preset.id ? "Selected" : "")
                            }
                            Button("save new…") { presetName = "My voice"; savingPreset = true }.buttonStyle(HardwareButton())
                        }
                        if session.pendingPresetID != nil {
                            HStack(spacing: 12) {
                                Text("Click the voice again to overwrite.").font(.system(size: 11, design: .monospaced))
                                Button("cancel") { session.cancelPresetOverwrite() }.buttonStyle(HardwareButton())
                                    .keyboardShortcut(.cancelAction)
                            }
                        }
                    }
                    if let message = session.message {
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(Panel.orange).frame(width: 7, height: 7).padding(.top, 4)
                            Text(message).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Divider().overlay(Panel.ink.opacity(0.12))
                    HStack(spacing: 16) {
                        Circle().fill(session.running ? Panel.orange : Panel.ink.opacity(0.3)).frame(width: 6, height: 6)
                        Text(session.running
                            ? session.driverInstalled ? "Connected as \(session.virtualMicName)" : "Monitoring \(session.selectedDevice?.name ?? "microphone")"
                            : session.driverInstalled ? "\(session.virtualMicName) is off" : "Virtual mic unavailable")
                            .font(.system(size: 11, design: .monospaced)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        if session.running {
                            Button("off", systemImage: "power") { session.stop() }.buttonStyle(HardwareButton())
                                .help("Stop microphone processing and send silence")
                        } else if session.driverInstalled {
                            Button("on", systemImage: "power") { Task { await session.start() } }.buttonStyle(HardwareButton()).disabled(!session.canStart)
                        } else {
                            Button(session.driverOnDisk ? "load mic" : "install mic") {
                                if session.driverOnDisk { session.reloadAudioService() } else { session.installDriver() }
                            }.buttonStyle(HardwareButton())
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        caption("LOCAL AUDIO / 48,000 Hz / GPLv3")
                        Spacer()
                        Button { showingSetup = true } label: {
                            Image(systemName: "questionmark.circle").font(.system(size: 16))
                        }.buttonStyle(.plain).foregroundStyle(Panel.ink.opacity(0.65))
                            .accessibilityLabel("Setup and permissions").help("Setup and permissions")
                    }
                }
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(LinearGradient(colors: [Panel.surface, Panel.ivory], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
        .foregroundStyle(Panel.ink)
        .onAppear { if !session.onboardingComplete { showingSetup = true } }
        .sheet(isPresented: $showingSetup) {
            SetupView(session: session) { session.completeOnboarding(); showingSetup = false }
        }
        .sheet(isPresented: $savingPreset) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Save voice preset").font(.title3.weight(.semibold))
                TextField("Preset name", text: $presetName).textFieldStyle(.plain)
                    .padding(12).background(RoundedRectangle(cornerRadius: 8).fill(Panel.ivory))
                    .onSubmit { saveVoice() }
                Text("Saves processing settings. Your microphone and headphone routing stay as they are. Existing names are updated.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("cancel") { savingPreset = false }.buttonStyle(HardwareButton()).keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("save") { saveVoice() }.buttonStyle(HardwareButton(selected: true, color: Panel.orange))
                        .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 310).background(Panel.surface).foregroundStyle(Panel.ink)
        }
    }

    private func saveVoice() {
        guard !presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        session.savePreset(name: presetName)
        savingPreset = false
    }

    private func sectionHeader(_ title: String, toggle: Binding<Bool>? = nil, toggleLabel: String = "") -> some View {
        HStack {
            caption(title)
            Spacer(minLength: 8)
            if let toggle {
                if toggleLabel == "Denoise" { caption("DENOISE") }
                Toggle(toggleLabel.isEmpty ? "Compressor" : toggleLabel, isOn: toggle).toggleStyle(HardwareToggle())
            }
        }.frame(height: 29)
    }

    private func display(narrow: Bool) -> some View {
        (narrow ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20)) : AnyLayout(HStackLayout(spacing: 25))) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(session.settings.bypass ? "DRY SIGNAL" : "VOICE SHAPING")
                    Spacer()
                    Text(session.running ? "● LIVE" : "○ STANDBY").foregroundStyle(session.running ? Panel.orange : Panel.lcd.opacity(0.5))
                }.font(.system(size: 11, design: .monospaced))
                EQDisplay(settings: session.settings).frame(height: 92)
                HStack { Text("40 Hz"); Spacer(); Text("280 Hz"); Spacer(); Text("3.5 kHz"); Spacer(); Text("16 kHz") }
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(Panel.lcd.opacity(0.55))
            }.frame(maxWidth: .infinity)
            if !narrow { Rectangle().fill(Panel.lcd.opacity(0.15)).frame(width: 1) }
            VStack(alignment: .leading, spacing: 14) {
                meter("IN", session.inputDB)
                meter("OUT", session.outputDB)
                HStack { Text("REDUCTION").opacity(0.6); Spacer(); Text(String(format: "%.1f dB", session.reductionDB)) }
                    .font(.system(size: 11, design: .monospaced))
                HStack(spacing: 14) {
                    Label(session.listening ? "Monitor On" : "Monitor Off", systemImage: "headphones")
                        .foregroundStyle(Panel.lcd.opacity(session.listening ? 0.85 : 0.5))
                    if session.settings.muted {
                        Label("Muted", systemImage: "mic.slash").foregroundStyle(Panel.orange)
                    }
                }.font(.system(size: 10, design: .monospaced))

            }.frame(maxWidth: narrow ? .infinity : 280)
        }.padding(23).foregroundStyle(Panel.lcd)
            .background {
                RoundedRectangle(cornerRadius: 11)
                    .fill(Panel.ivory.shadow(.inner(color: .black.opacity(0.4), radius: 4, x: 2, y: 3)))
                    .padding(-4)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.055, green: 0.065, blue: 0.06)
                        .shadow(.inner(color: .black.opacity(0.95), radius: 10, x: 2, y: 4)))
            }
            .overlay { LCDGlass().clipShape(RoundedRectangle(cornerRadius: 8)).allowsHitTesting(false).accessibilityHidden(true) }

    }
    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(0.6).foregroundStyle(Panel.ink.opacity(0.55))
    }
    private func key(_ text: String, _ symbol: String, on: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 17))
                HStack(spacing: 4) {
                    Circle().fill(on ? Color.white : Panel.ink.opacity(0.3)).frame(width: 4, height: 4)
                    Text(text).font(.system(size: 9, design: .monospaced)).fixedSize()
                }
            }
                .frame(width: 44, height: 44)
        }.buttonStyle(HardwareButton(selected: on, color: color, horizontalPadding: 10)).accessibilityLabel(text)
    }
    private func dial(_ title: String, _ subtitle: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ unit: String, _ color: Color) -> some View {
        Dial(title: title, subtitle: subtitle, value: value, range: range, unit: unit, color: color)
    }
    private func meter(_ title: String, _ db: Float) -> some View {
        VStack(spacing: 6) {
            HStack { Text(title); Spacer(); Text(db < -90 ? "−∞ dBFS" : String(format: "%.1f dBFS", db)) }.font(.system(size: 11, design: .monospaced))
            HStack(spacing: 3) {
                ForEach(0..<28, id: \.self) { index in
                    Rectangle().fill(db > -60 + Float(index) * 60 / 28 ? (index > 24 ? Panel.orange : Panel.lcd) : Panel.lcd.opacity(0.10)).frame(height: 8)
                }
            }
        }
    }
}

private struct HardwareButton: ButtonStyle {
    var selected = false
    var color = Panel.ivory
    var horizontalPadding: CGFloat = 15
    func makeBody(configuration: Configuration) -> some View {
        HardwareButtonFace(label: configuration.label, pressed: configuration.isPressed, selected: selected, color: color, horizontalPadding: horizontalPadding)
    }
}

private struct HardwareButtonFace<Label: View>: View {
    let label: Label
    let pressed: Bool
    let selected: Bool
    let color: Color
    let horizontalPadding: CGFloat
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        label.padding(.horizontal, horizontalPadding).padding(.vertical, 12)
            .foregroundStyle(selected ? Color.white : Panel.ink)
            .background {
                RoundedRectangle(cornerRadius: 11)
                    .fill(Panel.well.shadow(.inner(color: .black.opacity(0.25), radius: 3, x: 2, y: 3)))
                    .padding(-3)
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: selected
                        ? [color.opacity(0.8), color]
                        : [Panel.capTop, Panel.capBottom],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                    .shadow(.inner(color: Panel.rim.opacity(pressed ? 0.25 : 1), radius: 1, x: 1, y: 1))
                    .shadow(.inner(color: .black.opacity(pressed ? 0.22 : 0.06), radius: pressed ? 4 : 2, x: 1, y: 2)))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(
                        LinearGradient(colors: [Panel.rim, .black.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                    .shadow(color: Panel.highlight.opacity(pressed ? 0 : 1), radius: 4, x: -3, y: -3)
                    .shadow(color: .black.opacity(pressed ? 0.08 : 0.24), radius: pressed ? 1 : 5, x: pressed ? 0 : 3, y: pressed ? 1 : 5)
            }
            .brightness(hovered && enabled ? 0.025 : 0)
            .offset(y: pressed ? 2 : 0)
            .opacity(enabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
            .onHover { hovered = $0 }
    }
}

private struct Dial: View {
    let title: String
    let subtitle: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    let color: Color
    @State private var origin: Double?
    private var fraction: Double { min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound))) }
    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                ForEach(0..<25, id: \.self) { index in
                    Capsule().fill(Panel.ink.opacity(index % 6 == 0 ? 0.6 : 0.25)).frame(width: 1, height: index % 6 == 0 ? 6 : 3)
                        .offset(y: -43).rotationEffect(.degrees(-135 + Double(index) * 270 / 24))
                }
                Circle().fill(Panel.ivory.shadow(.inner(color: .black.opacity(0.26), radius: 4, x: 3, y: 4)))
                    .frame(width: 80, height: 80)
                    .shadow(color: Panel.highlight, radius: 3, x: -2, y: -2)
                Circle().fill(LinearGradient(colors: [Panel.capTop, Panel.capBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 71, height: 71)
                    .overlay(Circle().strokeBorder(Panel.rim, lineWidth: 1))
                    .shadow(color: .black.opacity(0.34), radius: 4, x: 2, y: 5)
                Circle().fill(LinearGradient(colors: [Color(red: 0.21, green: 0.23, blue: 0.22), .black], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 57, height: 57)
                    .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .black.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                Capsule().fill(color == Panel.ink ? Panel.lcd : color).frame(width: 3, height: 16).offset(y: -17).rotationEffect(.degrees(-135 + fraction * 270))
            }.frame(width: 92, height: 94).contentShape(Circle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                    if origin == nil { origin = value }
                    value = min(range.upperBound, max(range.lowerBound, origin! - event.translation.height / 180 * (range.upperBound - range.lowerBound)))
                }.onEnded { _ in origin = nil })
                .accessibilityElement().accessibilityLabel(title).accessibilityValue(String(format: "%.1f %@", value, unit))
                .accessibilityAdjustableAction { direction in
                    let step = (range.upperBound - range.lowerBound) / 100
                    if direction == .increment { value = min(range.upperBound, value + step) }
                    if direction == .decrement { value = max(range.lowerBound, value - step) }
                }
                .focusable()
                .onKeyPress(.upArrow) { value = min(range.upperBound, value + (range.upperBound-range.lowerBound)/100); return .handled }
                .onKeyPress(.downArrow) { value = max(range.lowerBound, value - (range.upperBound-range.lowerBound)/100); return .handled }
            Text(String(format: unit == "Hz" ? "%.0f %@" : "%.1f %@", value, unit)).font(.system(size: 13, design: .monospaced))
            Text(title).font(.system(size: 12, weight: .medium))
            Text(subtitle).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
        }.frame(width: 99, alignment: .leading)
    }
}

private struct EQDisplay: View {
    let settings: VoiceSettings
    var body: some View {
        Canvas { context, size in
            for row in 0...4 {
                var path = Path(); let y = Double(row) * size.height / 4
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(Panel.lcd.opacity(row == 2 ? 0.35 : 0.10)), lineWidth: 0.5)
            }
            var curve = Path()
            for index in 0...160 {
                let frequency = 40 * pow(400, Double(index) / 160)
                let db = settings.bypass ? 0 : response(frequency)
                let point = CGPoint(x: Double(index) / 160 * size.width, y: size.height * (0.5 - min(18, max(-18, db)) / 36))
                if index == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
            }
            context.stroke(curve, with: .color(Panel.orange), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }.accessibilityLabel("Equalizer frequency response")
    }
    private func response(_ frequency: Double) -> Double {
        let omega = 2 * Double.pi * frequency / 48000
        func magnitude(_ b0: Double, _ b1: Double, _ b2: Double, _ a1: Double, _ a2: Double) -> Double {
            let numerator = b0*b0 + b1*b1 + b2*b2 + 2*(b0*b1 + b1*b2)*cos(omega) + 2*b0*b2*cos(2*omega)
            let denominator = 1 + a1*a1 + a2*a2 + 2*(a1 + a1*a2)*cos(omega) + 2*a2*cos(2*omega)
            return 10 * log10(max(1e-12, numerator / max(1e-12, denominator)))
        }
        func bell(_ hz: Double, _ db: Double, _ q: Double) -> Double {
            let a = pow(10, db / 40), w = 2 * Double.pi * hz / 48000, alpha = sin(w) / (2*q), a0 = 1 + alpha/a
            let b1 = -2*cos(w)/a0
            return magnitude((1+alpha*a)/a0, b1, (1-alpha*a)/a0, b1, (1-alpha/a)/a0)
        }
        func shelf(_ hz: Double, _ db: Double, high: Bool) -> Double {
            let a = pow(10, db / 40), w = 2 * Double.pi * hz / 48000
            let c = cos(w), beta = sqrt(2 * a) * sin(w)
            if high {
                let a0 = (a+1) - (a-1)*c + beta
                return magnitude(a*((a+1)+(a-1)*c+beta)/a0, -2*a*((a-1)+(a+1)*c)/a0,
                    a*((a+1)+(a-1)*c-beta)/a0, 2*((a-1)-(a+1)*c)/a0, ((a+1)-(a-1)*c-beta)/a0)
            }
            let a0 = (a+1) + (a-1)*c + beta
            return magnitude(a*((a+1)-(a-1)*c+beta)/a0, 2*a*((a-1)-(a+1)*c)/a0,
                a*((a+1)-(a-1)*c-beta)/a0, -2*((a-1)+(a+1)*c)/a0, ((a+1)+(a-1)*c-beta)/a0)
        }
        var result = shelf(120, settings.bass, high: false) + bell(280, settings.mud, 0.8) + bell(3500, settings.presence, 0.7) + shelf(8000, settings.air, high: true)
        if settings.highPass > 0 {
            let w = 2 * Double.pi * settings.highPass / 48000, c = cos(w), alpha = sin(w)/sqrt(2), a0 = 1+alpha
            let b0 = (1+c)/(2*a0)
            result += magnitude(b0, -2*b0, b0, -2*c/a0, (1-alpha)/a0)
        }
        return result
    }
}

private struct LCDGlass: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    var lines = Path()
                    for row in stride(from: 0.0, to: size.height, by: 3) {
                        lines.move(to: CGPoint(x: 0, y: row))
                        lines.addLine(to: CGPoint(x: size.width, y: row))
                    }
                    context.stroke(lines, with: .color(.black.opacity(0.11)), lineWidth: 1)
                }
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.035), location: 0),
                    .init(color: .clear, location: 0.45),
                    .init(color: .black.opacity(0.06), location: 1)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                RoundedRectangle(cornerRadius: 8)
                    .fill(.clear.shadow(.inner(color: .black.opacity(0.8), radius: 13, x: 0, y: 0)))
                RadialGradient(colors: [.clear, .black.opacity(0.22)], center: .center,
                               startRadius: min(geometry.size.width, geometry.size.height) * 0.3,
                               endRadius: max(geometry.size.width, geometry.size.height) * 0.65)
            }
        }
    }
}


struct SetupView: View {
    @ObservedObject var session: Session
    let done: () -> Void
    @State private var page: Int
    init(session: Session, page: Int = 0, done: @escaping () -> Void) {
        self.session = session; self.done = done; self._page = State(initialValue: page)
    }
    private let titles = ["Choose your microphone", "Connect to recording apps", "Hear your adjustments"]
    private let symbols = ["mic", "waveform.path", "headphones"]
    private let explanations = [
        "Choose your microphone in Source. ClearMic asks for microphone access when you press Start or Listen. Allow it so the app can process your voice.",
        "The virtual microphone lets other apps receive your processed voice. Installing it requires a separate macOS installer and administrator approval. Loading it may briefly interrupt audio. You can test Listen before installing it.",
        "Choose headphones under Headphone Output, then turn on Listen. Its level controls only what you hear. Trim and Output control the voice sent to your recording app."
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("CLEARMIC SETUP").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Text("\(page + 1) / 3").font(.system(size: 11, design: .monospaced))
            }
            Image(systemName: symbols[page]).font(.system(size: 28)).foregroundStyle(Panel.orange)
            Text(titles[page]).font(.title2.weight(.medium))
            Text(explanations[page]).font(.body).fixedSize(horizontal: false, vertical: true)
            if page == 0 {
                Text("If access was denied, enable ClearMic in System Settings → Privacy & Security → Microphone.").font(.caption).foregroundStyle(.secondary)
            } else if page == 1 {
                Label(session.driverInstalled ? "Virtual microphone is available" : "Install from the main window when you're ready", systemImage: session.driverInstalled ? "checkmark.circle" : "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Use headphones to avoid feedback. Audio processing stays on this Mac.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if page > 0 { Button("back") { page -= 1 }.buttonStyle(HardwareButton()) }
                Spacer()
                Button(page == 2 ? "ready" : "next") {
                    if page == 2 { done() } else { page += 1 }
                }.buttonStyle(HardwareButton(selected: true, color: Panel.orange)).keyboardShortcut(.defaultAction)
            }.padding(.top, 6)
        }.padding(28).frame(width: 360, alignment: .leading).background(Panel.surface).foregroundStyle(Panel.ink)
    }
}
