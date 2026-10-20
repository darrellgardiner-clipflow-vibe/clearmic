import AppKit
import SwiftUI

private enum Panel {
    static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    static let ink = adaptive(NSColor(white: 0.18, alpha: 1), NSColor(white: 0.90, alpha: 1))
    static let ivory = adaptive(NSColor(red: 0.89, green: 0.88, blue: 0.84, alpha: 1), NSColor(white: 0.18, alpha: 1))
    static let surface = adaptive(NSColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1), NSColor(white: 0.25, alpha: 1))
    static let highlight = adaptive(NSColor(white: 1, alpha: 0.8), NSColor(white: 1, alpha: 0.08))
    static let orange = Color(red: 0.93, green: 0.26, blue: 0.10)
    static let blue = Color(red: 0.26, green: 0.43, blue: 0.56)
    static let lcd = Color(red: 0.77, green: 0.80, blue: 0.70)
}

struct ContentView: View {
    @ObservedObject var session: Session
    var body: some View {
        GeometryReader { geometry in
            let narrow = geometry.size.width < 820
            let compact = geometry.size.width < 440
            let stacked = geometry.size.width < 900
            ScrollView {
                VStack(spacing: 22) {
                    (narrow ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20)) : AnyLayout(HStackLayout())) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("clearmic").font(.system(size: 32, weight: .medium, design: .rounded)).tracking(-1.5)
                            caption("CM–01 / DESKTOP VOICE PROCESSOR")
                        }
                        if !narrow { Spacer() }
                        HStack(spacing: 12) {
                        key("bypass", "arrow.triangle.branch", on: session.settings.bypass, color: Panel.blue) { session.settings.bypass.toggle() }
                        key("mute", "mic.slash", on: session.settings.muted, color: Panel.orange) { session.settings.muted.toggle() }
                        key(session.running ? "stop" : "start", session.running ? "stop.fill" : "play.fill", on: session.running, color: Panel.orange) {
                            if session.running { session.stop() } else { Task { await session.start() } }
                        }.disabled(!session.running && !session.canStart)
                        }
                    }
                    (narrow ? AnyLayout(VStackLayout(alignment: .leading, spacing: 22)) : AnyLayout(HStackLayout(spacing: 22))) {
                        VStack(alignment: .leading, spacing: 8) {
                            caption("01 / SOURCE")
                            Picker("Microphone", selection: Binding(get: { session.settings.sourceUID }, set: session.selectSource)) {
                                Text("Select microphone").tag("")
                                if !session.settings.sourceUID.isEmpty && session.selectedDevice == nil {
                                    Text("Saved input disconnected").tag(session.settings.sourceUID)
                                }
                                ForEach(session.devices) { device in
                                    Text(device.sampleRate == 48000 ? device.name : "\(device.name) (\(Int(device.sampleRate / 1000)) kHz, unsupported)").tag(device.uid)
                                }
                            }.labelsHidden().frame(maxWidth: narrow ? .infinity : 240)
                            Picker("Channel", selection: $session.settings.channel) {
                                ForEach(0..<max(1, session.selectedDevice?.inputChannels ?? 1), id: \.self) { Text("Input \($0 + 1)").tag($0) }
                            }.frame(maxWidth: 160)
                        }
                        if !narrow { Divider().frame(height: 65) }
                        VStack(alignment: .leading, spacing: 8) {
                            caption("02 / HEADPHONE OUTPUT")
                            Picker("Headphone output", selection: $session.settings.monitorUID) {
                                Text("Select headphone output").tag("")
                                if !session.settings.monitorUID.isEmpty && session.selectedMonitor == nil {
                                    Text("Saved output disconnected").tag(session.settings.monitorUID)
                                }
                                ForEach(session.outputs) { Text($0.name).tag($0.uid) }
                            }.labelsHidden().frame(maxWidth: narrow ? .infinity : 240)
                            Text("Processed voice · use headphones").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        if !narrow { Spacer() }
                        key("listen", "headphones", on: session.settings.monitoring, color: Panel.blue) { session.settings.monitoring.toggle() }
                            .disabled(session.selectedMonitor == nil)
                    }
                    display(narrow: narrow)
                    (stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 24)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))) {
                        VStack(alignment: .leading, spacing: 12) {
                            caption("03 / SHAPE")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 99), spacing: 4)], spacing: 18) {
                                dial("trim", "INPUT", $session.settings.inputGain, -12...18, "dB", Panel.ink)
                                dial("rumble", "HIGH-PASS", $session.settings.highPass, 0...180, "Hz", Panel.ink)
                                dial("body", "280 Hz", $session.settings.mud, -12...6, "dB", Panel.blue)
                                dial("clarity", "3.5 kHz", $session.settings.presence, -6...9, "dB", Panel.orange)
                            }
                        }
                        if !stacked { Divider().frame(height: 185) }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                caption("04 / DYNAMICS")
                                Spacer()
                                Toggle("on", isOn: $session.settings.compression).font(.caption).toggleStyle(.checkbox)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 99), spacing: 4)], spacing: 18) {
                                dial("threshold", "COMPRESSOR", $session.settings.threshold, -40...0, "dB", Panel.ink)
                                dial("ratio", "COMPRESSION", $session.settings.ratio, 1...8, ":1", Panel.ink)
                                dial("output", "GAIN", $session.settings.makeup, -12...18, "dB", Panel.orange)
                            }
                        }
                    }
                    (narrow ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20)) : AnyLayout(HStackLayout(spacing: 14))) {
                        HStack(spacing: 14) {
                        Button("natural") { session.applyNatural() }.buttonStyle(HardwareButton())
                        Button("flat") { session.applyFlat() }.buttonStyle(HardwareButton())
                        }
                        if !narrow { Spacer(minLength: 0) }
                        HStack {
                        Image(systemName: "headphones").foregroundStyle(Panel.blue)
                        Text("listen level").font(.system(size: 11, design: .monospaced))
                        Slider(value: $session.settings.monitorGain, in: -48...0).frame(minWidth: 50, maxWidth: 135).tint(Panel.blue)
                        Text(String(format: "%.0f dB", session.settings.monitorGain)).font(.system(size: 11, design: .monospaced)).frame(width: 45)
                        }
                    }
                    (narrow ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(spacing: 10))) {
                        HStack(spacing: 10) {
                        Circle().fill(session.running ? Panel.blue : Panel.ink.opacity(0.25)).frame(width: 7, height: 7)
                        Text(session.message).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                        if !narrow { Spacer(minLength: 0) }
                        if !session.driverInstalled {
                            Button(session.driverOnDisk ? "load microphone" : "install microphone") {
                                if session.driverOnDisk { session.reloadAudioService() } else { session.installDriver() }
                            }.buttonStyle(HardwareButton())
                        }
                    }
                    (narrow ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())) {
                        caption("LOCAL AUDIO / 48,000 Hz / GPLv3")
                        if !narrow { Spacer() }
                        caption(session.driverInstalled ? "VIRTUAL MIC CONNECTED" : session.driverOnDisk ? "VIRTUAL MIC NEEDS LOADING" : "VIRTUAL MIC NOT INSTALLED")
                    }
                }
                .padding(compact ? 16 : narrow ? 22 : 32)
                .frame(maxWidth: .infinity)
            }
        }
        .background(LinearGradient(colors: [Panel.surface, Panel.ivory], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
        .foregroundStyle(Panel.ink)
    }

    private func display(narrow: Bool) -> some View {
        (narrow ? AnyLayout(VStackLayout(spacing: 20)) : AnyLayout(HStackLayout(spacing: 25))) {
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
                Text(session.settings.muted ? "MIC MUTED" : session.settings.monitoring ? "HEADPHONE MONITOR ON" : "HEADPHONE MONITOR OFF")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(session.settings.muted ? Panel.orange : Panel.lcd.opacity(0.6))
            }.frame(maxWidth: narrow ? .infinity : 280)
        }.padding(23).foregroundStyle(Panel.lcd)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color(red: 0.075, green: 0.085, blue: 0.08).shadow(.inner(color: .black.opacity(0.85), radius: 7, x: 3, y: 5)))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.black.opacity(0.75), lineWidth: 3))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(LinearGradient(colors: [.black.opacity(0.9), .white.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
                .shadow(color: Panel.highlight, radius: 1, x: 1, y: 2))
    }
    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(0.6).foregroundStyle(Panel.ink.opacity(0.55))
    }
    private func key(_ text: String, _ symbol: String, on: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) { Image(systemName: symbol).font(.system(size: 17)); Text(text).font(.system(size: 10, design: .monospaced)) }
                .frame(width: 55, height: 44)
        }.buttonStyle(HardwareButton(selected: on, color: color)).accessibilityLabel(text)
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
    func makeBody(configuration: Configuration) -> some View {
        HardwareButtonFace(label: configuration.label, pressed: configuration.isPressed, selected: selected, color: color)
    }
}

private struct HardwareButtonFace<Label: View>: View {
    let label: Label
    let pressed: Bool
    let selected: Bool
    let color: Color
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        label.padding(.horizontal, 15).padding(.vertical, 12)
            .foregroundStyle(selected ? Color.white : Panel.ink)
            .background {
                RoundedRectangle(cornerRadius: 11)
                    .fill(Panel.ink.opacity(0.18).shadow(.inner(color: .black.opacity(0.25), radius: 3, x: 2, y: 3)))
                    .padding(-3)
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: selected
                        ? [color.opacity(0.8), color]
                        : [Panel.surface, Panel.ivory],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                    .shadow(.inner(color: .white.opacity(pressed ? 0.12 : 0.65), radius: 1, x: 1, y: 1))
                    .shadow(.inner(color: .black.opacity(pressed ? 0.22 : 0.06), radius: pressed ? 4 : 2, x: 1, y: 2)))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.7), .black.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
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
                Circle().fill(LinearGradient(colors: [Panel.surface, Panel.ivory], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 71, height: 71)
                    .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
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
        }.frame(width: 99)
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
        var result = bell(280, settings.mud, 0.8) + bell(3500, settings.presence, 0.7)
        if settings.highPass > 0 {
            let w = 2 * Double.pi * settings.highPass / 48000, c = cos(w), alpha = sin(w)/sqrt(2), a0 = 1+alpha
            let b0 = (1+c)/(2*a0)
            result += magnitude(b0, -2*b0, b0, -2*c/a0, (1-alpha)/a0)
        }
        return result
    }
}
