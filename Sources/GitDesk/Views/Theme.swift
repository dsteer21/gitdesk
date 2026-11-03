import SwiftUI

enum Theme {
    static let background = Color(red: 0.11, green: 0.12, blue: 0.14)
    static let panel = Color(red: 0.14, green: 0.15, blue: 0.18)
    static let toolbar = Color(red: 0.09, green: 0.10, blue: 0.12)
    static let selection = Color(red: 0.20, green: 0.32, blue: 0.50)
    static let hover = Color.white.opacity(0.05)
    /// Muted blue (#324772) used instead of the bright system accent on the All Repositories screen.
    static let accent = Color(red: 50 / 255, green: 71 / 255, blue: 114 / 255)

    /// GitKraken-style lane colours.
    static let lanes: [Color] = [
        Color(red: 0.13, green: 0.71, blue: 0.86),
        Color(red: 0.58, green: 0.40, blue: 0.94),
        Color(red: 0.95, green: 0.33, blue: 0.62),
        Color(red: 0.98, green: 0.62, blue: 0.20),
        Color(red: 0.36, green: 0.80, blue: 0.40),
        Color(red: 0.96, green: 0.85, blue: 0.25),
        Color(red: 0.30, green: 0.50, blue: 0.98),
        Color(red: 0.93, green: 0.30, blue: 0.27),
    ]

    static func lane(_ index: Int) -> Color { lanes[index % lanes.count] }

    static func statusColour(_ status: Character) -> Color {
        switch status {
        case "A", "?": .green
        case "D": .red
        case "R", "C": .blue
        case "U": .purple
        default: .orange
        }
    }

    static func statusIcon(_ status: Character) -> String {
        switch status {
        case "A", "?": "plus.square.fill"
        case "D": "minus.square.fill"
        case "R", "C": "arrow.right.square.fill"
        case "U": "exclamationmark.triangle.fill"
        default: "pencil.line"
        }
    }

    /// UK-style date for the graph and details panels.
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f
    }()

    static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.unitsStyle = .short
        return f
    }()
}

/// Icon-over-label toolbar button, as in GitKraken.
struct ToolButton: View {
    let title: String
    let icon: String
    var badge: Int = 0
    var help: String?
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(height: 18)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(badge)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor))
                                .offset(x: 12, y: -6)
                        }
                    }
                Text(title).font(.system(size: 11))
            }
            .frame(minWidth: 50, minHeight: 40)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering && isEnabled ? Color.white.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 }
        .help(help ?? title)
    }
}

/// A toolbar button with a small drop-down of related actions.
struct SplitToolButton<MenuContent: View>: View {
    let title: String
    let icon: String
    var badge: Int = 0
    var help: String?
    let action: () -> Void
    @ViewBuilder let menu: () -> MenuContent

    var body: some View {
        HStack(spacing: -4) {
            ToolButton(title: title, icon: icon, badge: badge, help: help, action: action)
            Menu(content: menu) {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 16)
        }
    }
}

/// Small coloured label for branch/tag names in the graph.
struct RefPill: View {
    let text: String
    let icons: [String]
    let colour: Color
    var bold = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(icons, id: \.self) { Image(systemName: $0).font(.system(size: 9)) }
            Text(text).font(.system(size: 11, weight: bold ? .bold : .medium)).lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 4).fill(colour.opacity(0.28)))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(colour.opacity(0.8), lineWidth: 1))
    }
}

struct SectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: 4) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            if let count { Text("\(count)").font(.system(size: 10)).foregroundStyle(.tertiary) }
        }
    }
}
