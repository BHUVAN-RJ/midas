import SwiftUI
import WidgetKit

// The widget extension's entry point. One widget for now: the Folder (founder plan, 2026-10-11).

@main
struct MidasWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FolderWidget()
    }
}
