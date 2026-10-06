import SwiftUI

enum InterpreterStyle {
    static let fontScale: CGFloat = 1.05
    static let body = Font.system(size: NSFont.preferredFont(forTextStyle: .body).pointSize * fontScale)
    static let callout = Font.system(size: NSFont.preferredFont(forTextStyle: .callout).pointSize * fontScale)
    static let caption = Font.system(size: NSFont.preferredFont(forTextStyle: .caption1).pointSize * fontScale)
    static let headline = Font.system(size: NSFont.preferredFont(forTextStyle: .headline).pointSize * fontScale, weight: .semibold)

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * fontScale, weight: weight)
    }

    static let contentWidth: CGFloat = 1280
    static let pageInset: CGFloat = 24
    static let accent = Color.teal
    static let listening = Color.blue
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let inset = Color.primary.opacity(0.035)
    static let border = Color.primary.opacity(0.12)
}

struct InterpreterCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(InterpreterStyle.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(InterpreterStyle.border, lineWidth: 1)
            }
    }
}

struct InterpreterSectionHeading: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(InterpreterStyle.font(size: 19, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 39, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(InterpreterStyle.font(size: 16, weight: .semibold))
                Text(subtitle).font(InterpreterStyle.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct InterpreterStatus: View {
    let title: String
    let symbol: String
    var color: Color = .secondary

    var body: some View {
        Label(title, systemImage: symbol)
            .font(InterpreterStyle.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.08), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct InterpreterNotice: View {
    let message: String

    var body: some View {
        Label {
            Text(message).textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .font(InterpreterStyle.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 统一下拉控件的字号、边框与点击区域；选项直接放在第一层菜单。
struct InterpreterMenu<Options: View>: View {
    let title: String
    @ViewBuilder var options: Options

    var body: some View {
        Menu {
            options
        } label: {
            Text(title).font(InterpreterStyle.body).lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .tint(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(InterpreterStyle.inset, in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(InterpreterStyle.border) }
    }
}

struct InterpreterMenuOption: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
