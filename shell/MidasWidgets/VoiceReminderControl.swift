import AppIntents
import SwiftUI
import WidgetKit

/// "Ask jess" as a control (iOS 18): pick it under Settings → Action Button → Controls, or add
/// it to Control Center or the Lock Screen. It runs the same intent as the App Shortcut, which
/// opens Midas to the Listening screen. Its symbol is the written "Jess" (JessSymbols). The deployment target stays 17.0, so it is gated here and
/// in MidasWidgetsBundle.
@available(iOS 18.0, *)
struct VoiceReminderControl: ControlWidget {
    static let kind = "com.bhuvanrj.midas.new-reminder"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartVoiceReminderIntent()) {
                Label("Ask jess", image: JessSymbols.control)
            }
        }
        .displayName("Ask jess")
    }
}
