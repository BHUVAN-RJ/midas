import SwiftUI
import UIKit

/// The pill's one text area (B3 typing state, docs/mockups/repair-feedback-2026-10-23.html): the
/// spoken words, then what is typed, carrying on in the same text. Founder, on the phone
/// (2026-10-23): "the text that is typed sort of appears somewhere else" — the typed words used to
/// go into a second box on a line of their own under the spoken words.
///
/// The spoken words are a fixed start of the text: the caret never goes into them and Backspace
/// stops at them, so only `typed` changes. Words jess hears while the user types go in before the
/// typed words; the caret keeps its place in the typed words.
struct RepairPillTextView: UIViewRepresentable {
    /// The spoken words, already coloured (settled ink, the newest word grey). Empty when none.
    let spoken: NSAttributedString
    @Binding var typed: String
    @Binding var isTyping: Bool
    let font: UIFont
    let ink: UIColor
    /// The text area grows to this many lines, then scrolls, keeping the newest words in view.
    let maxLines: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(owner: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.font = font
        textView.tintColor = ink
        textView.returnKeyType = .done
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = false
        textView.delegate = context.coordinator
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.show(in: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.owner = self
        textView.font = font
        textView.tintColor = ink
        context.coordinator.show(in: textView)
        context.coordinator.matchFocus(of: textView, isTyping: isTyping)
    }

    /// As wide as offered; as tall as the text, up to `maxLines`, at least one line.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView textView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? textView.bounds.width
        guard width > 0, width.isFinite else {
            return nil
        }
        let lineHeight = font.lineHeight
        let fitted = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let tallest = (lineHeight * CGFloat(maxLines)).rounded(.up)
        let height = min(max(fitted.height, lineHeight.rounded(.up)), tallest)
        return CGSize(width: width, height: height)
    }

    /// The spoken words, a space, then the typed words, in one attributed text. The space is there
    /// only once there is something to type after the words.
    static func fullText(spoken: NSAttributedString, typed: String, isTyping: Bool, attributes: [NSAttributedString.Key: Any]) -> (text: NSAttributedString, typedStart: Int) {
        let text = NSMutableAttributedString(attributedString: spoken)
        text.addAttribute(.font, value: attributes[.font] as Any, range: NSRange(location: 0, length: text.length))
        if spoken.length > 0 && (isTyping || !typed.isEmpty) {
            text.append(NSAttributedString(string: " ", attributes: attributes))
        }
        let typedStart = text.length
        text.append(NSAttributedString(string: typed, attributes: attributes))
        return (text, typedStart)
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var owner: RepairPillTextView
        /// Where the typed words start in the text view (UTF-16).
        private var typedStart = 0

        init(owner: RepairPillTextView) {
            self.owner = owner
        }

        private var typingAttributes: [NSAttributedString.Key: Any] {
            [.font: owner.font, .foregroundColor: owner.ink]
        }

        /// Puts the spoken and typed words in the text view when they changed, keeping the caret
        /// the same distance from the end (so words heard while typing go in before it).
        func show(in textView: UITextView) {
            textView.typingAttributes = typingAttributes
            // Never replace the text under an unfinished keyboard composition
            guard textView.markedTextRange == nil else {
                return
            }
            let isTyping = owner.isTyping || textView.isFirstResponder
            let built = RepairPillTextView.fullText(spoken: owner.spoken, typed: owner.typed, isTyping: isTyping, attributes: typingAttributes)
            guard !Self.shows(built.text, typedStart: built.typedStart, in: textView) else {
                typedStart = built.typedStart
                return
            }
            let oldLength = (textView.text as NSString? ?? "").length
            let selection = textView.selectedRange
            let fromEnd = max(oldLength - (selection.location + selection.length), 0)
            textView.attributedText = built.text
            typedStart = built.typedStart
            let newLength = built.text.length
            let caret = min(max(newLength - fromEnd, typedStart), newLength)
            textView.selectedRange = NSRange(location: caret, length: 0)
            textView.typingAttributes = typingAttributes
            if !textView.isFirstResponder {
                showNewest(in: textView)
            }
        }

        /// The same words, and the spoken words in the same colours (the newest word turns ink
        /// once it is settled). The typed words' own attributes are left to the keyboard.
        private static func shows(_ text: NSAttributedString, typedStart: Int, in textView: UITextView) -> Bool {
            let current = textView.attributedText ?? NSAttributedString()
            guard current.string == text.string else {
                return false
            }
            let spokenRange = NSRange(location: 0, length: typedStart)
            let shownSpoken = current.attributedSubstring(from: spokenRange)
            let wantedSpoken = text.attributedSubstring(from: spokenRange)
            return shownSpoken.isEqual(to: wantedSpoken)
        }

        /// Scrolled to the bottom, so the newest words show once the text is taller than the pill.
        private func showNewest(in textView: UITextView) {
            let length = (textView.text as NSString? ?? "").length
            textView.scrollRangeToVisible(NSRange(location: length, length: 0))
        }

        /// SwiftUI's typing flag and the keyboard agree: drawing (which resigns) ends typing.
        func matchFocus(of textView: UITextView, isTyping: Bool) {
            guard textView.window != nil else {
                return
            }
            if isTyping && !textView.isFirstResponder {
                textView.becomeFirstResponder()
            } else if !isTyping && textView.isFirstResponder {
                textView.resignFirstResponder()
            }
        }

        // MARK: UITextViewDelegate

        func textViewDidBeginEditing(_ textView: UITextView) {
            // The space after the spoken words comes in now, and the caret goes after it
            show(in: textView)
            keepCaretInTypedWords(textView)
            if !owner.isTyping {
                owner.isTyping = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if owner.isTyping {
                owner.isTyping = false
            }
            show(in: textView)
            showNewest(in: textView)
        }

        /// A tap on the spoken words puts the caret after them; a selection may still cover them,
        /// to copy.
        func textViewDidChangeSelection(_ textView: UITextView) {
            keepCaretInTypedWords(textView)
        }

        private func keepCaretInTypedWords(_ textView: UITextView) {
            let selection = textView.selectedRange
            guard selection.length == 0, selection.location < typedStart else {
                return
            }
            textView.selectedRange = NSRange(location: typedStart, length: 0)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Return is Done
            if text == "\n" {
                textView.resignFirstResponder()
                return false
            }
            if range.location >= typedStart {
                return true
            }
            // An edit reaching into the spoken words changes only the typed part of it
            let start = typedStart
            let end = max(range.location + range.length, typedStart)
            let typedRange = NSRange(location: start - typedStart, length: end - start)
            let typedNow = owner.typed as NSString
            let newTyped = typedNow.replacingCharacters(in: typedRange, with: text)
            owner.typed = newTyped
            show(in: textView)
            let caret = start + (text as NSString).length
            textView.selectedRange = NSRange(location: caret, length: 0)
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            let all = textView.text as NSString? ?? ""
            let start = min(typedStart, all.length)
            let newTyped = all.substring(from: start)
            if newTyped != owner.typed {
                owner.typed = newTyped
            }
        }
    }
}
