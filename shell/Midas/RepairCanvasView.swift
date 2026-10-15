import SwiftUI

/// The repair layer over a frozen Sidekick (founder layout, 2026-10-13):
///
///   ✕                         ← Cancel, top left
///   frozen Sidekick, strokes in Tomato light
///   [ What to fix           ]  ← one-line text box
///   Undo      Clear   ● Send   ← ● red while listening
///
/// Shown by the host exactly where the web view is (same frame, bottom safe area ignored), so
/// the snapshot sits on the Sidekick it replaced and nothing looks like a screenshot.
struct RepairCanvasView: View {
    @Bindable var session: RepairSession
    @FocusState private var isTextBoxFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            drawingSurface
            cancelButton
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .background(Color.white)
        .task {
            await session.startListening()
        }
    }

    private var drawingSurface: some View {
        ZStack {
            Image(uiImage: session.snapshot)
                .resizable()
                .frame(width: session.viewSize.width, height: session.viewSize.height)
            RepairStrokesCanvas(strokes: session.allStrokes)
                .frame(width: session.viewSize.width, height: session.viewSize.height)
                .gesture(drawGesture)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .bottom)
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged(handleDragChanged)
            .onEnded(handleDragEnded)
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        isTextBoxFocused = false
        session.extendStroke(to: value.location)
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        session.endStroke()
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
                .focused($isTextBoxFocused)
                .submitLabel(.done)
            HStack {
                Button(RepairCopy.undoButton, action: session.undo)
                    .disabled(session.strokes.isEmpty)
                Spacer()
                Button(RepairCopy.clearButton, action: session.clear)
                    .disabled(session.strokes.isEmpty)
                Spacer()
                sendButton
            }
            .font(.body.weight(.medium))
            .tint(Color.primary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial)
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
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.primary)
        .disabled(!session.canSend)
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
