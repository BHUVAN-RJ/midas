import SwiftUI
import UIKit

/// The repair layer over a frozen Sidekick (founder layout, 2026-10-13):
///
///   ✕                         ← Cancel, top left
///   frozen Sidekick, strokes in Tomato light
///   [ What to fix           ]  ← one-line text box
///   Undo      Clear   ● Send   ← ● red while listening
///
/// Two layers, attached separately by `repairLayer` (first phone test, 2026-10-14: one stack
/// sized by the safe area overflowed, slid under the status bar and hid under the keyboard):
/// - `RepairFrozenView` takes the web view's own frame, so the frozen Sidekick sits pixel-exact on
///   the web view it replaced and never moves;
/// - `RepairControlsView` takes the safe frame, which the home indicator and the keyboard shrink,
///   so Cancel stays visible and the bottom bar floats over the bottom edge and rises with the
///   keyboard.
/// No colour here assumes light mode: the snapshot itself is the background.
struct RepairFrozenView: View {
    let session: RepairSession
    /// Measured frames, for tests; nil in the app.
    var onLayout: ((RepairLayerPart, CGRect) -> Void)?

    var body: some View {
        ZStack {
            Image(uiImage: session.snapshot)
                .resizable()
            RepairStrokesCanvas(strokes: session.allStrokes)
                .gesture(drawGesture)
        }
        .frame(width: session.viewSize.width, height: session.viewSize.height)
        .onGeometryChange(for: CGRect.self, of: RepairLayerPart.frameInWindow, action: recordSnapshot)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func recordSnapshot(_ frame: CGRect) {
        onLayout?(.snapshot, frame)
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged(handleDragChanged)
            .onEnded(handleDragEnded)
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        // Drawing puts the keyboard away; the text box lives in the other layer
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        session.extendStroke(to: value.location)
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        session.endStroke()
    }
}

/// Cancel, the text box and the buttons. Lets touches through everywhere else to the frozen
/// Sidekick below, where the user draws.
struct RepairControlsView: View {
    @Bindable var session: RepairSession
    var onLayout: ((RepairLayerPart, CGRect) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                cancelButton
                    .onGeometryChange(for: CGRect.self, of: RepairLayerPart.frameInWindow, action: recordCancel)
                Spacer()
            }
            Spacer()
            bottomBar
                .onGeometryChange(for: CGRect.self, of: RepairLayerPart.frameInWindow, action: recordBar)
        }
        .task {
            await session.startListening()
        }
    }

    private func recordCancel(_ frame: CGRect) {
        onLayout?(.cancel, frame)
    }

    private func recordBar(_ frame: CGRect) {
        onLayout?(.bottomBar, frame)
    }

    private func recordSend(_ frame: CGRect) {
        onLayout?(.send, frame)
    }

    private var cancelButton: some View {
        Button(action: session.cancel) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
                .padding(10)
                .background(.regularMaterial, in: Circle())
        }
        .accessibilityLabel(RepairCopy.cancelLabel)
        .padding(.leading, 16)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            TextField(RepairCopy.textPlaceholder, text: $session.typedText, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
            HStack {
                Button(RepairCopy.undoButton, action: session.undo)
                    .disabled(session.strokes.isEmpty)
                Spacer()
                Button(RepairCopy.clearButton, action: session.clear)
                    .disabled(session.strokes.isEmpty)
                Spacer()
                sendButton
                    .onGeometryChange(for: CGRect.self, of: RepairLayerPart.frameInWindow, action: recordSend)
            }
            .font(.body.weight(.medium))
            .tint(Color.primary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        // The material runs on under the home indicator and the keyboard; the controls do not
        .background(.regularMaterial, ignoresSafeAreaEdges: .bottom)
    }

    private var sendButton: some View {
        Button(action: session.send) {
            HStack(spacing: 6) {
                if session.isListening {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
                Text(RepairCopy.sendButton)
            }
            // The button is filled with the text colour (black, or white in dark mode); its word
            // takes the background colour so it shows in both
            .foregroundStyle(Color(uiColor: .systemBackground))
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.primary)
        .disabled(!session.canSend)
    }
}

/// The parts of the repair layer a test measures.
enum RepairLayerPart: Equatable, Sendable {
    case snapshot
    case cancel
    case bottomBar
    case send

    /// In window coordinates, so a test can compare them with the web view's frame.
    nonisolated static func frameInWindow(_ proxy: GeometryProxy) -> CGRect {
        proxy.frame(in: .global)
    }
}

extension View {
    /// A Sidekick's web view, full screen to the bottom edge, with the repair layer over it while a
    /// repair is open. Overlays, not a cover, so the freeze is instant. The frozen layer goes inside
    /// `ignoresSafeArea` to take the web view's own frame; the controls go outside it to take the
    /// safe frame, which the keyboard shrinks.
    func repairLayer(_ session: RepairSession?, onLayout: ((RepairLayerPart, CGRect) -> Void)? = nil) -> some View {
        overlay {
            if let session {
                RepairFrozenView(session: session, onLayout: onLayout)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .overlay {
            if let session {
                RepairControlsView(session: session, onLayout: onLayout)
            }
        }
    }
}

/// The strokes, drawn live; nothing else, so the frozen Sidekick shows through.
struct RepairStrokesCanvas: View {
    let strokes: [RepairStroke]

    var body: some View {
        Canvas(rendersAsynchronously: false, renderer: drawStrokes)
    }

    private func drawStrokes(context: inout GraphicsContext, size: CGSize) {
        let style = StrokeStyle(lineWidth: RepairPen.lineWidth, lineCap: .round, lineJoin: .round)
        for stroke in strokes {
            context.stroke(path(for: stroke), with: .color(RepairPen.color), style: style)
        }
    }

    private func path(for stroke: RepairStroke) -> Path {
        var path = Path()
        let points = stroke.points.filter(hasCoordinates).map(cgPoint)
        guard let first = points.first else {
            return path
        }
        path.move(to: first)
        if points.count == 1 {
            path.addLine(to: first)
        }
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func hasCoordinates(_ array: [Double]) -> Bool {
        array.count >= 2
    }

    private func cgPoint(_ array: [Double]) -> CGPoint {
        CGPoint(x: array[0], y: array[1])
    }
}
