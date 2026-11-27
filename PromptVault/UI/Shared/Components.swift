import SwiftUI

enum Design {
    static let rowCornerRadius: CGFloat = 8
    static let cardCornerRadius: CGFloat = 10
    static let favorite = Color.yellow
    static let variable = Color.accentColor
    static let builtIn = Color.teal
    static let popoverSize = CGSize(width: 400, height: 540)

    static let relativeFormat = Date.RelativeFormatStyle(presentation: .named, unitsStyle: .abbreviated)
}

extension Date {
    var relativeDescription: String { formatted(Design.relativeFormat) }
}

/// Wraps subviews onto multiple lines, like tags in a text field.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct TagChip: View {
    let name: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 3) {
            Text("#\(name)")
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Remove tag \(name)")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
        .foregroundStyle(.secondary)
    }
}

/// A small keyboard key glyph used for shortcut hints.
struct KeyCap: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 17)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
            )
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.regular)
                    .padding(.top, 4)
            }
        }
        .padding(28)
        .frame(maxWidth: 340)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: toast.symbol)
                .foregroundStyle(toast.isError ? Color.orange : Color.green)
            Text(toast.message)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
    }
}

/// The rounded-square glyph shown next to prompts.
struct PromptGlyph: View {
    let prompt: Prompt
    var size: CGFloat = 26

    private var symbol: String {
        if prompt.isTemplate { return "doc.on.doc" }
        return prompt.folder?.symbolName ?? "text.bubble"
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(Color.accentColor.opacity(0.13))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            )
            .accessibilityHidden(true)
    }
}

/// Small "{x} 3" badge indicating a prompt has fill-in variables.
struct VariableBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "curlybraces")
            Text("\(count)")
        }
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 4)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
        .help("\(count) fill-in variable\(count == 1 ? "" : "s")")
        .accessibilityLabel("\(count) variables")
    }
}

// MARK: - Highlighting

enum Highlighter {
    /// Bolds and tints the parts of `text` that match the search terms.
    static func searchMatches(in text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .filter { !$0.hasPrefix("#") }
            .map(String.init)
        guard !terms.isEmpty else { return attributed }
        for term in terms {
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
                if let range = Range(NSRange(found, in: text), in: attributed) {
                    attributed[range].foregroundColor = .accentColor
                    attributed[range].inlinePresentationIntent = .stronglyEmphasized
                }
                searchRange = found.upperBound..<text.endIndex
            }
        }
        return attributed
    }

    /// Prompt content with `{{placeholders}}` tinted (user variables in the accent color,
    /// built-ins in teal).
    static func placeholders(in text: String) -> AttributedString {
        var attributed = AttributedString(text)
        for placeholder in TemplateEngine.placeholders(in: text) {
            guard let range = Range(NSRange(placeholder.range, in: text), in: attributed) else { continue }
            let color = placeholder.isBuiltIn ? Design.builtIn : Design.variable
            attributed[range].foregroundColor = color
            attributed[range].backgroundColor = color.opacity(0.12)
            attributed[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return attributed
    }
}

/// Focuses a `.searchable` field on request (macOS 15+; a no-op on macOS 14).
struct SearchFocusModifier: ViewModifier {
    var isFocused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.searchFocused(isFocused)
        } else {
            content
        }
    }
}
