import SwiftUI
import UIKit

// The Editing tag cycles its word (founder, 2026-11-23, PRODUCT.md): while a code repair runs, the
// tag word cycles Reading… → Editing… → Checking… → Finishing… (about 2.5 s each, looping); the orb
// and the X stay. A question, Changed, Couldn't fix and Tap to update keep their own words.
// "On it" still shows first after this screen's Send, and "Taking longer" after 10 minutes.

/// The cycle's words and timing, in one place, pure so tests can check them.
enum RepairTagCycle {
    static let words = ["Reading…", "Editing…", "Checking…", "Finishing…"]
    /// How long each word shows.
    static let stepSeconds = 2.5
    /// The crossfade between two words, as the other tag word changes (0.2 s).
    static let crossFadeSeconds = 0.2

    /// The words at a moment: `from` fading out, `to` fading in; `mix` 0 is all `from`, 1 all `to`.
    struct Look: Equatable {
        let from: String
        let to: String
        let mix: Double
    }

    /// The tag in this state cycles: a code repair on its way, not yet "Taking longer".
    static func cycles(_ display: RepairTagDisplay) -> Bool {
        if case .repairing(_, let takingLonger) = display {
            return !takingLonger
        }
        return false
    }

    /// The cycle plays when the tag cycles and shows its own words (not "On it", not a word the
    /// open layer put in place of them).
    static func plays(display: RepairTagDisplay, shownWords: String) -> Bool {
        cycles(display) && shownWords == display.words
    }

    /// Which word, counting from the start of the cycle; before the start it is the first.
    static func step(at seconds: Double) -> Int {
        guard seconds > 0 else {
            return 0
        }
        return Int((seconds / stepSeconds).rounded(.down))
    }

    /// A word with the count when a second edit waits behind the first: "Reading… 2".
    static func word(forStep step: Int, count: Int = 1) -> String {
        let base = words[step % words.count]
        return count > 1 ? "\(base) \(count)" : base
    }

    static func word(at seconds: Double, count: Int = 1) -> String {
        word(forStep: step(at: seconds), count: count)
    }

    /// The words at a moment. Each new word crossfades in over `crossFadeSeconds`; with Reduce
    /// Motion it simply replaces the last one. The first word shows without a fade.
    static func look(at seconds: Double, count: Int = 1, reduceMotion: Bool) -> Look {
        let currentStep = step(at: seconds)
        let current = word(forStep: currentStep, count: count)
        let intoStep = seconds - Double(currentStep) * stepSeconds
        let isFading = !reduceMotion && currentStep > 0 && intoStep < crossFadeSeconds
        guard isFading else {
            return Look(from: current, to: current, mix: 1)
        }
        let previous = word(forStep: currentStep - 1, count: count)
        let mix = RepairSendMotion.easeInOut(intoStep / crossFadeSeconds)
        return Look(from: previous, to: current, mix: mix)
    }

    /// The words' width on the tag: the longest word's, so the tag does not jump as they change.
    static func wordsWidth(count: Int = 1) -> CGFloat {
        let font = UIFont.systemFont(ofSize: RepairTagSpec.fontSize, weight: .semibold)
        var widest: CGFloat = 0
        for step in words.indices {
            let shown = word(forStep: step, count: count) as NSString
            let measured = shown.size(withAttributes: [.font: font]).width.rounded(.up)
            widest = max(widest, measured)
        }
        return widest
    }

    /// When the cycle starts: right after "On it" when this screen sent the edit; otherwise when
    /// the edit was sent; nil when neither is known (the cycle then runs on the clock).
    static func startDate(lastSendAt: Date?, pendingSentAt: Date?) -> Date? {
        guard let sentAt = lastSendAt ?? pendingSentAt else {
            return nil
        }
        return sentAt.addingTimeInterval(RepairTagSpec.onItSeconds)
    }
}

/// The cycling words on the tag, at the width of the longest one. Redraws on its own clock, so the
/// rest of the tag (the orb, the X) is never rebuilt by it.
struct RepairTagCycleText: View {
    /// Where the cycle counts from; nil counts from the clock.
    let startedAt: Date?
    let count: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The cycle's start; with none, the clock's own start, so the words still change on the step.
    private var anchor: Date {
        startedAt ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    var body: some View {
        Group {
            if reduceMotion {
                // No crossfade: a redraw at each word change is enough
                TimelineView(.periodic(from: anchor, by: RepairTagCycle.stepSeconds)) { timeline in
                    words(at: timeline.date)
                }
            } else {
                TimelineView(.animation) { timeline in
                    words(at: timeline.date)
                }
            }
        }
        .frame(width: RepairTagCycle.wordsWidth(count: count), alignment: .leading)
    }

    private func seconds(at date: Date) -> Double {
        date.timeIntervalSince(anchor)
    }

    private func words(at date: Date) -> some View {
        let look = RepairTagCycle.look(at: seconds(at: date), count: count, reduceMotion: reduceMotion)
        return ZStack(alignment: .leading) {
            Text(look.from)
                .opacity(1 - look.mix)
            Text(look.to)
                .opacity(look.mix)
        }
        .font(.system(size: RepairTagSpec.fontSize, weight: .semibold))
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(look.to)
    }
}
