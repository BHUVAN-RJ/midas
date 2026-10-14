# Brief: repair-shell wiring (lead, after merging `agent/repair-shell`)

The repair shell (scribble, drawing layer, on-device speech, upload) is new files only on
`agent/repair-shell`. Nothing shows on the phone until these edits land in files the agent does
not own. Every symbol named below exists on the branch. About 35 lines in all.

## 1. `shell/Midas/MidasApp.swift`

`SidekickWebView.makeUIView`, after the web view is made:

```swift
let scribble = ScribbleGestureRecognizer(target: context.coordinator, action: #selector(SidekickNavigationGuard.startRepair))
webView.addGestureRecognizer(scribble)
context.coordinator.webView = webView
```

On the coordinator (`SidekickNavigationGuard`, or a small new coordinator that wraps it):

```swift
weak var webView: WKWebView?
var onRepairSession: ((RepairSession) -> Void)?

@objc func startRepair() {
    guard let webView else { return }
    Task { @MainActor in
        let session = await RepairSession.begin(sidekickId: sidekickId, webView: webView, transcriber: OnDeviceSpeechTranscriber(), uploader: ShellServices.shared.repairUploader)
        if let session { onRepairSession?(session) }
    }
}
```

`SidekickScreen`: hold `@State private var repairSession: RepairSession?`, pass a setter down
to the web view's coordinator, and show the layer as an overlay (not a cover: the freeze must be
instant and sit exactly on the web view):

```swift
.overlay {
    if let repairSession {
        RepairCanvasView(session: repairSession)
    }
}
.onChange(of: repairSession) { _, session in
    session?.onFinish = { repairSession = nil }
}
```

## 2. `shell/Midas/ShellServices.swift`

```swift
let repairUploader: RepairUploader
// in init:
let repairAPI = RemoteRepairUploadAPI(platformOrigin: PlatformConfig.platformOrigin, session: .shared, sessionToken: ShellServices.currentSessionToken)
self.repairUploader = RepairUploader(api: repairAPI, outbox: RepairOutbox(directoryURL: RepairOutbox.defaultDirectoryURL()))
```

`MidasApp.handleScenePhaseChange`, case `.active`, one more task:

```swift
Task { @MainActor in
    await ShellServices.shared.repairUploader.retryQueued()
}
```

## 3. `shell/Midas/SidekickBundleLoader.swift`

`RemoteSidekickBundleLoader.loadBundle`, after `bundle(from:response:)` succeeds, so the report
can say which bundle and scope the user was on:

```swift
let scope = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: SidekickBundleVersions.scopeHeader)
SidekickBundleVersions.shared.record(sidekickId: sidekickId, version: bundle.version, scope: scope)
```

## 4. `shell/project.yml`, Midas target `info.properties`

App-wide, generic strings (founder, 2026-10-13: they also serve the voice assistant):

```yaml
        # Asked the first time a voice feature is used (repair layer; the voice assistant later).
        NSMicrophoneUsageDescription: "Midas uses the microphone for voice features."
        NSSpeechRecognitionUsageDescription: "Midas turns your voice into text on this iPhone."
```

Then a test that both keys are present with these strings (same shape as
`BackgroundRefreshConfigTests`). Left out of the branch so it is not red before the strings land.

## 5. `docs/DESIGN.md`, section 2.2

Record the first assigned use of the accent: the repair pen is Tomato light `#FF6347`
(founder, 2026-10-13). Code: `RepairPen` in `shell/Midas/RepairSession.swift`.

## Ask to `repair-intake` (POST /repairs)

Parts the shell sends beyond the contract's list; intake decides storage:

| Part | Type | Why |
|---|---|---|
| `transcriptWords` | JSON `[{word,startMs,endMs}]`, ms on the stroke clock | enhancement 1 |
| `typedText` | text | what was typed in the box; `transcript` already holds it after the spoken words |
| `clientReportId` | UUID | a retry after a lost response must not make a second row |
| `bundleScope` | `user` \| `base` | from `X-Midas-Bundle-Scope` at bundle load |
| `device`, `iosVersion`, `appVersion`, `appBuild` | text | the contract's "device and app version", named |

`kind` is always `unknown` from the shell: a hint; the agent decides from the transcript
(`bug` | `change` | `feature`). Max body size wanted from intake; the shell sends about 0.5–2 MB.
