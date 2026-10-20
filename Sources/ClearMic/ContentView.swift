import SwiftUI

private enum Panel {
    static let ink = Color(red: 0.18, green: 0.19, blue: 0.18)
    static let ivory = Color(red: 0.89, green: 0.88, blue: 0.84)
    static let orange = Color(red: 0.93, green: 0.26, blue: 0.10)
    static let blue = Color(red: 0.26, green: 0.43, blue: 0.56)
    static let lcd = Color(red: 0.77, green: 0.80, blue: 0.70)
}

struct ContentView: View {
    @ObservedObject var session: Session
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("clearmic").font(.system(size: 32, weight: .medium, design: .rounded)).tracking(-1.5)
                        caption("CM–01 / DESKTOP VOICE PROCESSOR")
                    }
                    Spacer()
                    key("bypass", "arrow.triangle.branch", on: session.settings.bypass, color: Panel.blue) { session.settings.bypass.toggle() }
                    key("mute", "mic.slash", on: session.settings.muted, color: Panel.orange) { session.settings.muted.toggle() }
                    key(session.running ? "stop" : "start", session.running ? "stop.fill" : "play.fill", on: session.running, color: Panel.orange) {
                        if session.running { session.stop() } else { Task { await session.start() } }
                    }.disabled(!session.running && !session.canStart)
                }
                HStack(spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        caption("01 / SOURCE")
                        Picker("Microphone", selection: $session.settings.sourceUID) {
                            Text("Select microphone").tag("")
                            if !session.settings.sourceUID.isEmpty && session.selectedDevice == nil {
                                Text("Saved input disconnected").tag(session.settings.sourceUID)
                            }
                            ForEach(session.devices) { Text($0.name).tag($0.uid) }
                        }.labelsHidden().frame(width: 240)
                        Picker("Channel", selection: $session.settings.channel) {
                            ForEach(0..<max(1, session.selectedDevice?.inputChannels ?? 1), id: \.self) { Text("Input \($0 + 1)").tag($0) }
                        }.frame(width: 160)
                    }
                    Divider().frame(height: 65)
                    VStack(alignment: .leading, spacing: 8) {
                        caption("02 / HEADPHONE OUTPUT")
                        Picker("Headphone output", selection: $session.settings.monitorUID) {
                            Text("Select headphone output").tag("")
                            if !session.settings.monitorUID.isEmpty && session.selectedMonitor == nil {
                                Text("Saved output disconnected").tag(session.settings.monitorUID)
                            }
                            ForEach(session.outputs) { Text($0.name).tag($0.uid) }
                        }.labelsHidden().frame(width: 240)
                        Text("Processed voice · use headphones").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    key("listen", "headphones", on: session.settings.monitoring, color: Panel.blue) { session.settings.monitoring.toggle() }
                        .disabled(session.selectedMonitor == nil)
                }
                display
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        caption("03 / SHAPE")
                        HStack(spacing: 4) {
                            dial("trim", "INPUT", $session.settings.inputGain, -12...18, "dB", Panel.ink)
                            dial("rumble", "HIGH-PASS", $session.settings.highPass, 0...180, "Hz", Panel.ink)
                            dial("body", "280 Hz", $session.settings.mud, -12...6, "dB", Panel.blue)
                            dial("clarity", "3.5 kHz", $session.settings.presence, -6...9, "dB", Panel.orange)
                        }
                    }
                    Spacer(minLength: 4)
                    Divider().frame(height: 185)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            caption("04 / DYNAMICS")
                            Spacer()
                            Toggle("on", isOn: $session.settings.compression).font(.caption).toggleStyle(.checkbox)
                        }
                        HStack(spacing: 4) {
                            dial("threshold", "COMPRESSOR", $session.settings.threshold, -40...0, "dB", Panel.ink)
                            dial("ratio", "COMPRESSION", $session.settings.ratio, 1...8, ":1", Panel.ink)
                            dial("output", "GAIN", $session.settings.makeup, -12...18, "dB", Panel.orange)
                        }
                    }
                }
                HStack(spacing: 14) {
                    Button("natural") { session.applyNatural() }.buttonStyle(HardwareButton())
                    Button("flat") { session.applyFlat() }.buttonStyle(HardwareButton())
                    Spacer()
                    Image(systemName: "headphones").foregroundStyle(Panel.blue)
                    Text("listen level").font(.system(size: 11, design: .monospaced))
                    Slider(value: $session.settings.monitorGain, in: -48...0).frame(width: 135).tint(Panel.blue)
                    Text(String(format: "%.0f dB", session.settings.monitorGain)).font(.system(size: 11, design: .monospaced)).frame(width: 45)
                }
                HStack(spacing: 10) {
                    Circle().fill(session.running ? Panel.blue : Panel.ink.opacity(0.25)).frame(width: 7, height: 7)
                    Text(session.message).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Spacer(minLength: 0)
                    if !session.driverInstalled {
                        Button(session.driverOnDisk ? "load microphone" : "install microphone") {
                            if session.driverOnDisk { session.reloadAudioService() } else { session.installDriver() }
                        }.buttonStyle(HardwareButton())
                    }
                }
                HStack {
                    caption("LOCAL AUDIO / 48,000 Hz / GPLv3")
                    Spacer()
                    caption(session.driverInstalled ? "VIRTUAL MIC CONNECTED" : session.driverOnDisk ? "VIRTUAL MIC NEEDS LOADING" : "VIRTUAL MIC NOT INSTALLED")
                }
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 18)
                .fill(LinearGradient(colors: [Color.white.opacity(0.65), Panel.ivory], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 10)
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.8), lineWidth: 1)))
            .padding(18)
        }
        .background(Color(red: 0.72, green: 0.73, blue: 0.71))
        .foregroundStyle(Panel.ink).preferredColorScheme(.light)
    }

    private var display: some View {
        HStack(spacing: 25) {
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
            Rectangle().fill(Panel.lcd.opacity(0.15)).frame(width: 1)
            VStack(alignment: .leading, spacing: 14) {
                meter("IN", session.inputDB)
                meter("OUT", session.outputDB)
                HStack { Text("REDUCTION").opacity(0.6); Spacer(); Text(String(format: "%.1f dB", session.reductionDB)) }
                    .font(.system(size: 11, design: .monospaced))
                Text(session.settings.muted ? "MIC MUTED" : session.settings.monitoring ? "HEADPHONE MONITOR ON" : "HEADPHONE MONITOR OFF")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(session.settings.muted ? Panel.orange : Panel.lcd.opacity(0.6))
            }.frame(width: 280)
        }.padding(23).foregroundStyle(Panel.lcd)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color(red: 0.075, green: 0.085, blue: 0.08))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.black.opacity(0.75), lineWidth: 3))
                .shadow(color: .white.opacity(0.85), radius: 0, x: 0, y: 1))
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
        configuration.label.padding(.horizontal, 12).padding(.vertical, 9).foregroundStyle(selected ? Color.white : Panel.ink)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? color : Panel.ivory)
                .shadow(color: .black.opacity(configuration.isPressed ? 0.05 : 0.22), radius: configuration.isPressed ? 0 : 2, x: 0, y: configuration.isPressed ? 0 : 3)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(selected ? 0.1 : 0.65), lineWidth: 1)))
            .offset(y: configuration.isPressed ? 2 : 0)
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
                Circle().fill(LinearGradient(colors: [.white, Color(red: 0.72, green: 0.72, blue: 0.68)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 71, height: 71).shadow(color: .black.opacity(0.28), radius: 3, x: 1, y: 4)
                Circle().fill(LinearGradient(colors: [Color(red: 0.21, green: 0.23, blue: 0.22), .black], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 57, height: 57)
                Capsule().fill(color == Panel.ink ? Panel.ivory : color).frame(width: 3, height: 16).offset(y: -17).rotationEffect(.degrees(-135 + fraction * 270))
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
