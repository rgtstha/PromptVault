import AppKit
import SwiftUI

/// A plain-text editor (NSTextView) that live-highlights `{{variables}}`.
/// Smart quotes/dashes are disabled because prompts are often code.
struct PromptTextEditor: NSViewRepresentable {
    @Binding var text: String
    var monospaced = false
    var fontSize: CGFloat = 13
    var placeholder = ""

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.textContainer?.lineFragmentPadding = 4
        textView.setAccessibilityLabel("Prompt content")

        let placeholderLabel = NSTextField(labelWithString: placeholder)
        placeholderLabel.textColor = .placeholderTextColor
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 12),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8),
        ])
        context.coordinator.placeholderLabel = placeholderLabel

        textView.string = text
        context.coordinator.applyStyle(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let styleChanged = coordinator.parent.monospaced != monospaced || coordinator.parent.fontSize != fontSize
        coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        coordinator.placeholderLabel?.stringValue = placeholder
        if textView.string != text, !textView.hasMarkedText() {
            let selection = textView.selectedRanges
            textView.string = text
            let length = (text as NSString).length
            textView.selectedRanges = selection.map { value in
                let range = value.rangeValue
                let location = min(range.location, length)
                return NSValue(range: NSRange(location: location, length: min(range.length, length - location)))
            }
            coordinator.applyStyle(to: textView)
        } else if styleChanged {
            coordinator.applyStyle(to: textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptTextEditor
        weak var placeholderLabel: NSTextField?

        init(parent: PromptTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyStyle(to: textView)
        }

        private var baseFont: NSFont {
            parent.monospaced
                ? .monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
                : .systemFont(ofSize: parent.fontSize)
        }

        func applyStyle(to textView: NSTextView) {
            placeholderLabel?.isHidden = !textView.string.isEmpty
            placeholderLabel?.font = baseFont
            guard let storage = textView.textStorage else { return }
            let string = textView.string
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2.5
            let base: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
            let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
            storage.beginEditing()
            storage.setAttributes(base, range: NSRange(location: 0, length: storage.length))
            for placeholder in TemplateEngine.placeholders(in: string) {
                let color: NSColor = placeholder.isBuiltIn ? .systemTeal : .controlAccentColor
                storage.addAttributes([
                    .foregroundColor: color,
                    .backgroundColor: color.withAlphaComponent(0.13),
                    .font: boldFont,
                ], range: NSRange(placeholder.range, in: string))
            }
            storage.endEditing()
            textView.typingAttributes = base
        }
    }
}
