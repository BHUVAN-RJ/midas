#if MIDAS_TEST_BUILD
// Build 41: the keyboard experience (TEST BUILD, founder 2026-11-22; branch agent/dictation-test,
// never merged; docs/briefs/dictation-keyboard-test.md, "Build 41"). Compiled into the Midas Test
// app and the MidasKeyboard extension.
//
// Build 40 worked on the founder's phone: Apple's 🎙 types, the Midas keyboard stays up and cleans
// up. Build 41 is the look and feel around it, with Wispr Flow's keyboard as the reference: a top
// bar (undo; ✕ cancel while Apple listens), then the numbers and symbols rows, then ABC · space ·
// return. ABC goes to the next keyboard (Apple's letters and emoji). Apple's own key sounds and a
// light haptic on every key; a soft one when listening starts and when the cleaned text lands.
//
// This file is the pure part (the tests drive it): the numbers-first pages, which sound and haptic
// each key gets, the cancel plan, the undo stack and the motion with and without Reduce Motion.
import Foundation

/// The fixed numbers of the build 41 keyboard.
enum DictationKeyboardExperienceConstants {
    /// The keyboard's height on iPhone 16 Pro: top bar, four rows of Apple-sized keys, padding.
    static let keyboardHeight: Double = 262
    static let topBarHeight: Double = 44
    /// After ✕, the keyboard logs what Apple's dictation does for this long.
    static let cancelWatch: TimeInterval = 3.0
    /// At most this many "after cancel" lines per cancel.
    static let cancelWatchLines = 6
    /// Undo keeps this many cleanups and cancels.
    static let undoLimit = 10
    /// Undo checks the text before the cursor still ends with this much of the text after the edit
    /// (iOS's context window may drop text from the front).
    static let undoMatchTail = 40
}

// MARK: The pages (numbers first, like Wispr Flow)

/// The two pages of the numbers-first keyboard.
enum DictationNumbersPage: String, Equatable, Sendable, CaseIterable {
    case numbers
    /// "#+=": the second symbols page, as Apple's.
    case symbols
}

/// The numbers-first keyboard in keyboardMic "apple": no letters page; ABC goes to the next keyboard.
struct DictationNumbersLayout: Equatable, Sendable {
    private(set) var page: DictationNumbersPage = .numbers

    static let numberRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'"],
    ]

    static let symbolRows: [[String]] = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"],
        [".", ",", "?", "!", "'"],
    ]

    /// The three character rows of the page showing.
    var rows: [[String]] {
        page == .numbers ? Self.numberRows : Self.symbolRows
    }

    /// The key left of the third row: "#+=" on numbers, "123" on symbols.
    var pageKeyLabel: String {
        page == .numbers ? "#+=" : "123"
    }

    /// Each appearance starts on numbers.
    mutating func appeared() {
        page = .numbers
    }

    mutating func handle(_ control: DictationKeyboardControl) -> [DictationKeyboardEffect] {
        switch control {
        case .abc, .nextKeyboard:
            // Letters and emoji come from the next keyboard (Apple's), as Wispr Flow does
            return [.nextKeyboard]
        case .symbols:
            page = page == .numbers ? .symbols : .numbers
            return []
        case .numbers:
            page = .numbers
            return []
        case .character(let character):
            return [.insert(character)]
        case .space:
            return [.insert(" ")]
        case .backspace:
            return [.deleteBackward]
        case .returnKey:
            return [.insert("\n")]
        case .listen, .shift, .shiftLock:
            // Not on this keyboard: Apple's 🎙 listens, and there are no letters to shift
            return []
        }
    }
}

// MARK: Sounds and haptics

/// Which of Apple's keyboard sounds a key gets.
enum DictationKeyKind: String, Equatable, Sendable, CaseIterable {
    case character
    case delete
    /// shift, #+=, 123, ABC, space, return, 🌐, undo, ✕.
    case modifier

    static func of(_ control: DictationKeyboardControl) -> DictationKeyKind {
        switch control {
        case .character:
            return .character
        case .backspace:
            return .delete
        case .abc, .numbers, .symbols, .listen, .nextKeyboard, .shift, .shiftLock, .space, .returnKey:
            return .modifier
        }
    }

    /// Apple's system keyboard sounds: key press click, delete, modifier.
    var systemSoundID: UInt32 {
        switch self {
        case .character:
            return 1104
        case .delete:
            return 1155
        case .modifier:
            return 1156
        }
    }
}

/// How a key's sound plays.
enum DictationKeySound: Equatable, Sendable {
    /// Apple's own sound for the key kind (needs Full Access).
    case system(UInt32)
    /// UIDevice.playInputClick(): the one click, following the Keyboard Clicks setting; works
    /// without Full Access.
    case inputClick
}

enum DictationHaptic: String, Equatable, Sendable {
    /// Every key press, like Apple's keyboard haptics.
    case light
    /// Listening starts; the cleaned text lands.
    case soft
}

/// Moments that get a soft haptic.
enum DictationFeedbackMoment: String, Equatable, Sendable {
    case listeningStarted = "listening-started"
    case textLanded = "text-landed"
}

/// What a key press or a moment plays. Haptics need Full Access; without it, only the input click.
struct DictationKeyboardFeedbackPlan: Equatable, Sendable {
    let sound: DictationKeySound?
    let haptic: DictationHaptic?

    static func forKey(_ kind: DictationKeyKind, hasFullAccess: Bool) -> DictationKeyboardFeedbackPlan {
        guard hasFullAccess else {
            return DictationKeyboardFeedbackPlan(sound: .inputClick, haptic: nil)
        }
        return DictationKeyboardFeedbackPlan(sound: .system(kind.systemSoundID), haptic: .light)
    }

    static func forMoment(_ moment: DictationFeedbackMoment, hasFullAccess: Bool) -> DictationKeyboardFeedbackPlan {
        DictationKeyboardFeedbackPlan(sound: nil, haptic: hasFullAccess ? .soft : nil)
    }

    /// The keyboard log's line on what this keyboard can play.
    static func availabilityDetail(hasFullAccess: Bool, inputClicksEnabled: Bool, reduceMotion: Bool) -> String {
        let sounds = hasFullAccess ? "sounds Apple 1104/1155/1156" : "sounds input click only"
        let haptics = hasFullAccess ? "haptics light per key, soft on listen and landing" : "haptics off (no full access)"
        return "full access " + (hasFullAccess ? "on" : "off") + ", " + sounds + ", " + haptics
            + ", input clicks " + (inputClicksEnabled ? "enabled" : "not enabled")
            + ", Keyboard Clicks setting not readable by a keyboard"
            + ", reduce motion " + (reduceMotion ? "on" : "off")
    }
}

// MARK: Cancel ✕

/// What ✕ did with the running dictation's text.
enum DictationAppleCancelResult: String, Equatable, Sendable, CaseIterable {
    /// The span was deleted.
    case deleted
    /// The text before the cursor no longer ends with the span.
    case textChanged = "text-changed"
    /// The span is unknown (the text changed elsewhere).
    case contextLost = "context-lost"
    /// Apple had typed nothing yet.
    case empty
}

struct DictationAppleCancelPlan: Equatable, Sendable {
    let result: DictationAppleCancelResult
    let deleteCount: Int
    /// The span deleted (empty when skipped).
    let removed: String

    /// The text before the cursor after the plan is carried out.
    func contextAfter(_ contextNow: String?) -> String {
        String((contextNow ?? "").dropLast(deleteCount))
    }

    /// "deleted 18" or "skipped: text-changed".
    var detail: String {
        result == .deleted ? "deleted \(deleteCount)" : "skipped: " + result.rawValue
    }
}

enum DictationAppleCancel {
    /// Delete exactly what this dictation typed, when the text before the cursor still ends with it.
    static func plan(span: String?, contextNow: String?) -> DictationAppleCancelPlan {
        guard let span else {
            return DictationAppleCancelPlan(result: .contextLost, deleteCount: 0, removed: "")
        }
        guard !span.isEmpty else {
            return DictationAppleCancelPlan(result: .empty, deleteCount: 0, removed: "")
        }
        guard let contextNow, contextNow.hasSuffix(span) else {
            return DictationAppleCancelPlan(result: .textChanged, deleteCount: 0, removed: "")
        }
        return DictationAppleCancelPlan(result: .deleted, deleteCount: span.count, removed: span)
    }
}

// MARK: Undo

/// One change Midas made to the person's text (a cleanup or a cancel).
struct DictationKeyboardEdit: Equatable, Sendable {
    /// What Midas deleted.
    let removed: String
    /// What Midas inserted in its place.
    let added: String
    /// The text before the cursor right after the edit.
    let contextAfter: String
}

enum DictationKeyboardUndoResult: String, Equatable, Sendable {
    case undone
    /// The text changed since the edit: nothing undone, and the older edits are dropped.
    case textChanged = "text-changed"
    case nothing
}

struct DictationKeyboardUndoPlan: Equatable, Sendable {
    let result: DictationKeyboardUndoResult
    let deleteCount: Int
    let insertText: String
    /// The text before the cursor after the undo.
    let contextAfter: String

    var detail: String {
        result == .undone ? "undone: deleted \(deleteCount), inserted \(insertText.count)" : "skipped: " + result.rawValue
    }
}

/// Undo for the cleanups and cancels Midas made (typing a key clears it: Apple's undo is in the
/// host's own menu for typing).
struct DictationKeyboardUndo: Equatable, Sendable {
    private(set) var edits: [DictationKeyboardEdit] = []

    var canUndo: Bool {
        !edits.isEmpty
    }

    mutating func record(_ edit: DictationKeyboardEdit) {
        edits.append(edit)
        let overflow = edits.count - DictationKeyboardExperienceConstants.undoLimit
        if overflow > 0 {
            edits.removeFirst(overflow)
        }
    }

    mutating func clear() {
        edits = []
    }

    /// The plan for the newest edit; it applies only while the text is still as Midas left it.
    mutating func undo(contextNow: String?) -> DictationKeyboardUndoPlan {
        let text = contextNow ?? ""
        guard let last = edits.last else {
            return DictationKeyboardUndoPlan(result: .nothing, deleteCount: 0, insertText: "", contextAfter: text)
        }
        guard Self.isUnchanged(text, since: last) else {
            edits = []
            return DictationKeyboardUndoPlan(result: .textChanged, deleteCount: 0, insertText: "", contextAfter: text)
        }
        edits.removeLast()
        let contextAfter = String(text.dropLast(last.added.count)) + last.removed
        return DictationKeyboardUndoPlan(result: .undone, deleteCount: last.added.count, insertText: last.removed, contextAfter: contextAfter)
    }

    /// The same text as right after the edit; a long text only needs the same last 40 characters.
    static func isUnchanged(_ contextNow: String, since edit: DictationKeyboardEdit) -> Bool {
        guard contextNow.hasSuffix(edit.added) else {
            return false
        }
        if contextNow == edit.contextAfter {
            return true
        }
        let tailLength = DictationKeyboardExperienceConstants.undoMatchTail
        guard edit.contextAfter.count >= tailLength else {
            return false
        }
        return contextNow.hasSuffix(String(edit.contextAfter.suffix(tailLength)))
    }
}

// MARK: Motion

/// Keys ↔ listening view: a 250 ms spring with no bounce (docs/DESIGN.md: no spring bounces) that
/// slides and fades; with Reduce Motion a short cross-fade only.
struct DictationKeyboardMotion: Equatable, Sendable {
    let duration: Double
    let slides: Bool
    let bounce: Double

    static let standardDuration = 0.25
    static let reducedDuration = 0.15

    static func forReduceMotion(_ reduceMotion: Bool) -> DictationKeyboardMotion {
        reduceMotion
            ? DictationKeyboardMotion(duration: reducedDuration, slides: false, bounce: 0)
            : DictationKeyboardMotion(duration: standardDuration, slides: true, bounce: 0)
    }
}
#endif
