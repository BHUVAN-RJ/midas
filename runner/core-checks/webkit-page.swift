// The shield's page opener (docs/briefs/repair-lanes.md W1, "Page opens"): loads a Sidekick's
// index.html in WebKit (macOS WKWebView, the same engine the iPhone shell runs, headless, no
// window), once per step of a plan, and prints one JSON array with what each step reported.
//
// Usage: webkit-page <plan.json>
//   plan.json: { "htmlPath": "...", "baseUrl": "https://<id>.sidekick.invalid/",
//                "steps": [ { "nonce": "...", "prelude": "<script source>" } ],
//                "stepTimeoutMs": 8000, "width": 402, "height": 874 }
//
// Each step loads the page fresh with its own prelude injected at document start. The prelude
// (page-prelude.js, filled in by page-open.mjs) answers the page's store, records console errors
// and posts one message to the "shield" handler when the step is done. A message is accepted only
// when it carries the step's nonce, so a page cannot post a made-up report of its own.
//
// Output: [ { "step": 0, "report": { ... } } | { "step": 0, "timedOut": true } ]
// Exit codes: 0 when every step ran (pass or fail is the caller's to judge), 2 on a bad plan.
import AppKit
import WebKit

struct PlanStep: Decodable {
    let nonce: String
    let prelude: String
}

struct Plan: Decodable {
    let htmlPath: String
    let baseUrl: String
    let steps: [PlanStep]
    let stepTimeoutMs: Int
    let width: Double
    let height: Double
}

@MainActor
final class StepRunner: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    static let handlerName = "shield"

    private let plan: Plan
    private let html: String
    private let baseURL: URL
    private let contentController = WKUserContentController()
    private let webView: WKWebView
    private var stepIndex = 0
    private var results: [[String: Any]] = []
    // Bumped every step, so a late timer from an earlier step never ends the current one.
    private var stepGeneration = 0

    init(plan: Plan, html: String, baseURL: URL) {
        self.plan = plan
        self.html = html
        self.baseURL = baseURL
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        let frame = NSRect(x: 0, y: 0, width: plan.width, height: plan.height)
        webView = WKWebView(frame: frame, configuration: configuration)
        super.init()
        contentController.add(self, name: Self.handlerName)
        webView.navigationDelegate = self
    }

    func start() {
        runCurrentStep()
    }

    private func runCurrentStep() {
        guard stepIndex < plan.steps.count else {
            finish()
            return
        }
        stepGeneration += 1
        let generation = stepGeneration
        let step = plan.steps[stepIndex]
        contentController.removeAllUserScripts()
        let preludeScript = WKUserScript(source: step.prelude, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        contentController.addUserScript(preludeScript)
        webView.loadHTMLString(html, baseURL: baseURL)
        let deadline = DispatchTime.now() + .milliseconds(plan.stepTimeoutMs)
        DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
            self?.stepTimedOut(generation: generation)
        }
    }

    private func stepTimedOut(generation: Int) {
        guard generation == stepGeneration else {
            return
        }
        results.append(["step": stepIndex, "timedOut": true])
        advance()
    }

    private func advance() {
        stepIndex += 1
        runCurrentStep()
    }

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body as? String
        MainActor.assumeIsolated {
            self.acceptReport(body)
        }
    }

    private func acceptReport(_ body: String?) {
        guard stepIndex < plan.steps.count, let body, let data = body.data(using: .utf8) else {
            return
        }
        guard let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        // Only the prelude knows the nonce; anything else posting here is ignored
        guard (report["nonce"] as? String) == plan.steps[stepIndex].nonce else {
            return
        }
        results.append(["step": stepIndex, "report": report])
        advance()
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let text = error.localizedDescription
        MainActor.assumeIsolated {
            self.navigationFailed(text)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let text = error.localizedDescription
        MainActor.assumeIsolated {
            self.navigationFailed(text)
        }
    }

    private func navigationFailed(_ text: String) {
        guard stepIndex < plan.steps.count else {
            return
        }
        results.append(["step": stepIndex, "loadError": text])
        advance()
    }

    private func finish() {
        let data = (try? JSONSerialization.data(withJSONObject: results)) ?? Data("[]".utf8)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(0)
    }
}

func failWithBadPlan(_ reason: String) -> Never {
    FileHandle.standardError.write(Data("webkit-page: \(reason)\n".utf8))
    exit(2)
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    failWithBadPlan("usage: webkit-page <plan.json>")
}
guard let planData = FileManager.default.contents(atPath: arguments[1]) else {
    failWithBadPlan("cannot read \(arguments[1])")
}
guard let plan = try? JSONDecoder().decode(Plan.self, from: planData) else {
    failWithBadPlan("plan is not valid JSON of the expected shape")
}
guard let html = try? String(contentsOfFile: plan.htmlPath, encoding: .utf8) else {
    failWithBadPlan("cannot read \(plan.htmlPath)")
}
guard let baseURL = URL(string: plan.baseUrl) else {
    failWithBadPlan("bad baseUrl")
}

// No Dock icon, no menu bar, no window: WKWebView draws offscreen
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let runner = MainActor.assumeIsolated {
    StepRunner(plan: plan, html: html, baseURL: baseURL)
}
MainActor.assumeIsolated {
    runner.start()
}
application.run()
