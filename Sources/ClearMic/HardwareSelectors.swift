import SwiftUI

struct HardwareSelector<Selection: Hashable, Options: View>: View {
    let title: String
    let value: String
    @Binding var selection: Selection
    @ViewBuilder let options: () -> Options

    init(_ title: String, value: String, selection: Binding<Selection>, @ViewBuilder options: @escaping () -> Options) {
        self.title = title
        self.value = value
        self._selection = selection
        self.options = options
    }

    var body: some View {
        Menu {
            Picker(title, selection: $selection, content: options).pickerStyle(.inline)
        } label: {
            HStack(spacing: 12) {
                Text(value).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(Panel.ink.opacity(0.6))
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(Panel.ink)
            .padding(.horizontal, 13).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(Panel.ivory.shadow(.inner(color: .black.opacity(0.18), radius: 4, x: 2, y: 3)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                    LinearGradient(colors: [.black.opacity(0.18), Panel.highlight], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
                .shadow(color: Panel.highlight, radius: 1, x: 1, y: 2))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(title).accessibilityValue(value)
    }
}

struct HardwareToggle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                Text(configuration.isOn ? "ON" : "OFF")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Panel.ink.opacity(0.7))
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill((configuration.isOn ? Panel.orange : Panel.ink.opacity(0.2))
                        .shadow(.inner(color: .black.opacity(0.3), radius: 3, x: 1, y: 2)))
                    Capsule().fill(LinearGradient(colors: [Panel.capTop, Panel.capBottom], startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule().strokeBorder(Panel.highlight, lineWidth: 1))
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 2)
                        .frame(width: 23, height: 23).padding(3)
                }.frame(width: 49, height: 29)
                    .overlay(Capsule().strokeBorder(Panel.ink.opacity(0.15), lineWidth: 1))
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        }
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isOn)
    }
}
