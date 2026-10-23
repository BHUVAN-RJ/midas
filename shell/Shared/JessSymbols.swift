import Foundation

// jess outside the app (founder, 2026-10-23, docs/mockups/jess-shortcuts-2026-10-23.html): controls
// take our own symbol, the written "Jess" (G8); the Shortcuts tile, Spotlight and the Action
// button's Shortcut take only Apple's symbols, so they show the sound wave (S2) on a grayBlue tile,
// with an ink Spotlight platter (ShortcutsPlatter / ShortcutsTint in Info.plist).
enum JessSymbols {
    /// The custom symbol in Shared.xcassets, drawn by shell/icon-source/jess-symbol.py.
    static let control = "JessSymbol"
    /// The SF Symbol for the App Shortcut.
    static let shortcut = "waveform"
    /// Asset colours named in Info.plist for the App Shortcuts platter in Spotlight.
    static let platterColour = "ShortcutsPlatter"
    static let platterTint = "ShortcutsTint"
}
