import AppKit
import SwiftData
import SwiftUI
import Testing
@testable import PromptVault

/// Renders the main screens to PNG files for visual review. Opt-in: runs only when
/// `PROMPTVAULT_SNAPSHOT_DIR` is set (pass `TEST_RUNNER_PROMPTVAULT_SNAPSHOT_DIR=/path` to xcodebuild).
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PROMPTVAULT_SNAPSHOT_DIR"] != nil))
final class SnapshotRenderTests {
    private var cleanups: [() -> Void] = []
    deinit { MainActor.assumeIsolated { cleanups.forEach { $0() } } }

    private let outputDirectory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PROMPTVAULT_SNAPSHOT_DIR"] ?? NSTemporaryDirectory())

    private func makeApp() throws -> AppModel {
        let (app, cleanup) = try makeTestAppModel()
        cleanups.append(cleanup)
        // Realistic usage data.
        let prompts = app.library.prompts
        for (index, prompt) in prompts.enumerated() {
            for _ in 0..<((index * 7) % 13) { app.library.recordUse(of: prompt) }
        }
        if let review = prompts.first(where: { $0.title == "Thorough Code Review" }) {
            var draft = PromptDraft(review)
            draft.content = review.content.replacingOccurrences(of: "meticulous senior engineer", with: "meticulous staff engineer")
                + "\nFinish with a one-paragraph summary."
            app.library.update(review, with: draft)
        }
        return app
    }

    @Test func renderPopoverScreens() async throws {
        let app = try makeApp()
        let review = try #require(app.library.prompts.first { $0.title == "Thorough Code Review" })
        let kickoff = try #require(app.library.prompts.first { $0.title == "Expert Project Kickoff" })

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            app.popover.route = .list
            app.popover.selectedID = nil
            try await render(PopoverRootView().environment(app), size: Design.popoverSize, appearance: appearance, name: "popover-list-\(suffix)")

            app.popover.searchText = "review"
            try await render(PopoverRootView().environment(app), size: Design.popoverSize, appearance: appearance, name: "popover-search-\(suffix)")
            app.popover.searchText = ""

            app.popover.route = .preview(review.id)
            try await render(PopoverRootView().environment(app), size: Design.popoverSize, appearance: appearance, name: "popover-preview-\(suffix)")

            app.popover.route = .fill(kickoff.id)
            try await render(PopoverRootView().environment(app), size: Design.popoverSize, appearance: appearance, name: "popover-fill-\(suffix)")

            app.popover.route = .edit(kickoff.id)
            try await render(PopoverRootView().environment(app), size: Design.popoverSize, appearance: appearance, name: "popover-edit-\(suffix)")
        }
    }

    @Test func renderLibraryAndSettings() async throws {
        let app = try makeApp()
        let review = try #require(app.library.prompts.first { $0.title == "Thorough Code Review" })
        let size = CGSize(width: 1180, height: 760)

        let tableRows = try await renderWindow(LibraryRootView().environment(app), size: size, name: "library-overview")
        // Sidebar rendering uses vibrancy, which offscreen capture can't draw, so also verify the
        // actual table contents: the sidebar (collections + folders + tags) and the prompt list.
        try tableRows.map(String.init).joined(separator: ",").write(
            to: outputDirectory.appendingPathComponent("library-table-rows.txt"), atomically: true, encoding: .utf8
        )
        #expect(tableRows.contains(app.library.prompts.count), "Prompt list shows every prompt")
        #expect(tableRows.contains { $0 >= LibraryScope.smartCollections.count + app.library.rootFolders.count }, "Sidebar has rows")

        app.libraryState.select(review, library: app.library)
        try await renderWindow(LibraryRootView().environment(app), size: size, name: "library-editor")

        app.libraryState.showHistory = true
        try await renderWindow(LibraryRootView().environment(app), size: CGSize(width: 1400, height: 760), name: "library-history")
        app.libraryState.showHistory = false

        try await renderWindow(SettingsView().environment(app), size: CGSize(width: 540, height: 500), name: "settings", bridging: false)
    }

    // MARK: Rendering

    private func render<V: View>(_ view: V, size: CGSize, appearance: NSAppearance.Name, name: String) async throws {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        try await Task.sleep(for: .milliseconds(400))
        hosting.layoutSubtreeIfNeeded()
        try write(hosting, name: name)
        window.close()
    }

    @discardableResult
    private func renderWindow<V: View>(_ view: V, size: CGSize, name: String, bridging: Bool = true) async throws -> [Int] {
        let controller = NSHostingController(rootView: view)
        if bridging { controller.sceneBridgingOptions = [.toolbars, .title] }
        let window = NSWindow(contentViewController: controller)
        window.styleMask = bridging ? [.titled, .closable, .resizable, .fullSizeContentView] : [.titled, .closable]
        window.title = bridging ? "PromptVault" : "PromptVault Settings"
        window.toolbarStyle = .unified
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(size)
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(900))
        let frameView = window.contentView?.superview ?? controller.view
        try write(frameView, name: name)
        let rows = tableRowCounts(in: frameView)
        window.orderOut(nil)
        window.close()
        return rows
    }

    private func tableRowCounts(in view: NSView) -> [Int] {
        var counts: [Int] = []
        if let table = view as? NSTableView { counts.append(table.numberOfRows) }
        for subview in view.subviews { counts += tableRowCounts(in: subview) }
        return counts
    }

    private func write(_ view: NSView, name: String) throws {
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try data.write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }
}
