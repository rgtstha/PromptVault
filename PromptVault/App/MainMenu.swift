import AppKit

/// The application menu bar (visible while a PromptVault window is active). It also provides the
/// Edit menu key equivalents (⌘C, ⌘V, ⌘Z…) that text fields need, including in the popover.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        return main
    }

    /// Menu shown when right-clicking the menu bar icon.
    static func statusItemMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Open PromptVault", #selector(AppDelegate.showPopover(_:))))
        menu.addItem(item("Open Library", #selector(AppDelegate.showLibraryWindow(_:))))
        menu.addItem(item("New Prompt…", #selector(AppDelegate.newPrompt(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Import Prompts…", #selector(AppDelegate.importPrompts(_:))))
        menu.addItem(item("Back Up Now", #selector(AppDelegate.backUpNow(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(AppDelegate.showSettings(_:))))
        menu.addItem(item("Quit PromptVault", #selector(NSApplication.terminate(_:)), key: "q"))
        return menu
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "PromptVault")
        menu.addItem(item("About PromptVault", #selector(AppDelegate.showAbout(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(AppDelegate.showSettings(_:)), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Hide PromptVault", #selector(NSApplication.hide(_:)), key: "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit PromptVault", #selector(NSApplication.terminate(_:)), key: "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New Prompt", #selector(AppDelegate.newPrompt(_:)), key: "n"))
        menu.addItem(item("New Folder", #selector(AppDelegate.newFolder(_:)), key: "n", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Import Prompts…", #selector(AppDelegate.importPrompts(_:)), key: "i", modifiers: [.command, .shift]))
        menu.addItem(item("Export Selected Prompts…", #selector(AppDelegate.exportSelected(_:))))
        menu.addItem(item("Export All Prompts…", #selector(AppDelegate.exportAll(_:)), key: "e", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Back Up Now", #selector(AppDelegate.backUpNow(_:))))
        menu.addItem(item("Restore from Backup…", #selector(AppDelegate.restoreBackup(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), key: "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), key: "z"))
        menu.addItem(item("Redo", Selector(("redo:")), key: "z", modifiers: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), key: "v", modifiers: [.command, .option, .shift]))
        menu.addItem(item("Delete", #selector(NSText.delete(_:))))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), key: "a"))
        menu.addItem(.separator())
        menu.addItem(item("Find Prompts…", #selector(AppDelegate.findPrompts(_:)), key: "f"))
        let findInText = item("Find in Prompt Text…", #selector(NSTextView.performFindPanelAction(_:)), key: "f", modifiers: [.command, .option])
        findInText.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        menu.addItem(findInText)
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), key: "f", modifiers: [.command, .control]))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Library", #selector(AppDelegate.showLibraryWindow(_:)), key: "l"))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
