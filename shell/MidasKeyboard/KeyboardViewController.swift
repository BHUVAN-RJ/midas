// The Midas keyboard extension's entry (TEST BUILD, founder 2026-11-14; branch
// agent/dictation-test, never merged; docs/briefs/dictation-keyboard-test.md). Hosts the SwiftUI
// keys and hands typing to the text proxy.
//
// Build 40 (founder 2026-11-22): passes every public signal of Apple's dictation to the model (the
// input mode changing, textWillChange / textDidChange, viewDidAppear / viewWillDisappear) and
// reports the input mode and hasDictationKey for the keyboard log. No private calls.
//
// Build 41 (founder 2026-11-22): the input view adopts UIInputViewAudioFeedback; keys play Apple's
// own keyboard sounds (system sounds 1104 / 1155 / 1156) and a light haptic, a soft one when
// listening starts and when the cleaned text lands.
import AudioToolbox
import SwiftUI
import UIKit

/// Build 41: the keyboard's input view, so iOS plays input clicks for it (UIDevice.playInputClick).
final class MidasKeyboardInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool {
        true
    }
}

final class KeyboardViewController: UIInputViewController, MidasKeyboardHost {
    private static let keyboardHeight = CGFloat(DictationKeyboardExperienceConstants.keyboardHeight)
    private static let appGroup = Bundle.main.object(forInfoDictionaryKey: "MidasAppGroup") as? String ?? "group.com.bhuvanrj.midas.test"

    private var model: MidasKeyboardModel?
    private var hostingController: UIHostingController<MidasKeyboardView>?
    nonisolated(unsafe) private var inputModeObserver: NSObjectProtocol?
    // Build 41: prepared ahead so the first key's haptic is not late
    private let keyHaptic = UIImpactFeedbackGenerator(style: .light)
    private let softHaptic = UIImpactFeedbackGenerator(style: .soft)

    override func loadView() {
        let keyboardView = MidasKeyboardInputView(frame: .zero, inputViewStyle: .keyboard)
        keyboardView.allowsSelfSizing = true
        view = keyboardView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let keyboardModel = MidasKeyboardModel(hasFullAccess: hasFullAccess, appGroup: Self.appGroup)
        keyboardModel.host = self
        model = keyboardModel
        let hosting = UIHostingController(rootView: MidasKeyboardView(model: keyboardModel))
        hosting.view.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hosting)
        view.addSubview(hosting.view)
        let heightConstraint = view.heightAnchor.constraint(equalToConstant: Self.keyboardHeight)
        // Below required, so iOS's own sizing wins during rotation without a conflict
        heightConstraint.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            heightConstraint,
        ])
        hosting.didMove(toParent: self)
        hostingController = hosting
        observeInputMode()
    }

    deinit {
        if let inputModeObserver {
            NotificationCenter.default.removeObserver(inputModeObserver)
        }
    }

    /// Build 40: iOS posts this when the input mode changes (dictation among them, if it does).
    private func observeInputMode() {
        let center = NotificationCenter.default
        inputModeObserver = center.addObserver(forName: UITextInputMode.currentInputModeDidChangeNotification, object: nil, queue: .main,
                                               using: makeInputModeHandler())
    }

    private func makeInputModeHandler() -> @Sendable (Notification) -> Void {
        { [weak self] notification in
            let mode = notification.object as? UITextInputMode
            let language = mode?.primaryLanguage
            MainActor.assumeIsolated {
                self?.model?.inputModeChanged(notificationLanguage: language)
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model?.needsGlobeKey = needsInputModeSwitchKey
        keyHaptic.prepare()
        softHaptic.prepare()
        model?.appeared()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        model?.didAppear()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model?.disappeared()
    }

    override func textWillChange(_ textInput: (any UITextInput)?) {
        super.textWillChange(textInput)
        model?.textWillChange()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        model?.textChanged()
    }

    // MARK: MidasKeyboardHost

    var contextBeforeInput: String? {
        textDocumentProxy.documentContextBeforeInput
    }

    var contextAfterInput: String? {
        textDocumentProxy.documentContextAfterInput
    }

    var documentIdentifier: UUID {
        textDocumentProxy.documentIdentifier
    }

    /// Build 40: the document's input mode language ("dictation" while Apple dictates, if iOS says so),
    /// else this keyboard's own.
    var inputModeLanguage: String? {
        textDocumentProxy.documentInputMode?.primaryLanguage ?? textInputMode?.primaryLanguage
    }

    /// Build 40, for the keyboard log: every input mode iOS reports, and hasDictationKey.
    var signalDetail: String {
        let documentMode = textDocumentProxy.documentInputMode?.primaryLanguage ?? "none"
        let ownMode = textInputMode?.primaryLanguage ?? "none"
        return "document mode " + documentMode + ", keyboard mode " + ownMode + ", hasDictationKey " + (hasDictationKey ? "true" : "false")
            + ", needsInputModeSwitchKey " + (needsInputModeSwitchKey ? "true" : "false")
    }

    // MARK: Build 41: sounds and haptics

    var inputClicksEnabled: Bool {
        (view as? UIInputViewAudioFeedback)?.enableInputClicksWhenVisible ?? false
    }

    var reduceMotion: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    func playFeedback(_ plan: DictationKeyboardFeedbackPlan) {
        switch plan.sound {
        case .system(let soundID):
            AudioServicesPlaySystemSound(SystemSoundID(soundID))
        case .inputClick:
            UIDevice.current.playInputClick()
        case nil:
            break
        }
        switch plan.haptic {
        case .light:
            keyHaptic.impactOccurred()
            keyHaptic.prepare()
        case .soft:
            softHaptic.impactOccurred()
            softHaptic.prepare()
        case nil:
            break
        }
    }

    func insertText(_ text: String) {
        textDocumentProxy.insertText(text)
    }

    func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    func advanceToNextKeyboard() {
        advanceToNextInputMode()
    }

    /// Keyboards cannot call UIApplication.shared; the responder chain reaches the extension's
    /// application object, whose openURL:options:completionHandler: opens Midas Test (the way other
    /// dictation keyboards do; fine for a test build).
    func openStartURL() {
        let url = DictationKeyboardConstants.startURL as NSURL
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication, application.responds(to: selector) {
                typealias OpenURLFunction = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let implementation = application.method(for: selector)
                let openURL = unsafeBitCast(implementation, to: OpenURLFunction.self)
                openURL(application, selector, url, NSDictionary(), nil)
                return
            }
            responder = current.next
        }
    }
}
