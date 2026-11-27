import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click to record a new global shortcut. Esc cancels, Delete clears.
struct ShortcutRecorder: View {
    let combo: KeyCombo?
    let onChange: (KeyCombo?) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var rejected = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 120)
                    .foregroundStyle(isRecording ? Color.accentColor : .primary)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(isRecording ? "Recording shortcut" : "Global shortcut \(label)")

            if combo != nil && !isRecording {
                Button {
                    onChange(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove shortcut")
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if isRecording { return rejected ? "Add ⌘, ⌥ or ⌃…" : "Type shortcut…" }
        return combo?.displayString ?? "Record Shortcut"
    }

    private func startRecording() {
        isRecording = true
        rejected = false
        HotKeyCenter.shared.unregister() // so the current shortcut can be re-recorded
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            onChange(combo) // re-register the existing shortcut
        }
    }

    private func handle(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers.isEmpty && keyCode == UInt32(kVK_Escape) {
            stopRecording()
            return
        }
        if modifiers.isEmpty && (keyCode == UInt32(kVK_Delete) || keyCode == UInt32(kVK_ForwardDelete)) {
            finish(with: nil)
            return
        }
        let candidate = KeyCombo(keyCode: keyCode, modifiers: modifiers)
        guard candidate.isValidGlobalShortcut else {
            rejected = true
            NSSound.beep()
            return
        }
        finish(with: candidate)
    }

    private func finish(with newCombo: KeyCombo?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        onChange(newCombo)
    }
}

/// Inline word-level diff rendering.
struct DiffText: View {
    let segments: [DiffEngine.Segment]

    var body: some View {
        Text(attributed)
            .font(.system(size: 12))
            .lineSpacing(2)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.text)
            switch segment.kind {
            case .equal:
                break
            case .inserted:
                part.backgroundColor = Color.green.opacity(0.22)
                part.foregroundColor = Color.primary
            case .removed:
                part.backgroundColor = Color.red.opacity(0.18)
                part.strikethroughStyle = .single
                part.foregroundColor = Color.secondary
            }
            result += part
        }
        return result
    }
}
