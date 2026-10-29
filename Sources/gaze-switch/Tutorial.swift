import AppKit
import GazeSwitchCore
import SwiftUI

final class TutorialModel: ObservableObject {
    @Published var scrollMode: ScrollMode
    @Published var status = "Looking for you…"
    let eyeScrollEdge: Double
    let hotkey: String
    var onScrollModeChange: (ScrollMode) -> Void = { _ in }

    init(config: Config) {
        scrollMode = config.scrollMode
        eyeScrollEdge = config.eyeScrollEdge
        hotkey = config.hotkey
    }
}

/// Explains hand and eye scrolling. The window is itself the practice area: looking at it
/// activates it, and pinching or looking at its edges scrolls it.
final class TutorialWindowController {
    let model: TutorialModel
    private let window: NSWindow
    private var lastUpdate = -Double.infinity

    init(config: Config) {
        model = TutorialModel(config: config)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "How to Scroll"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: TutorialView(model: model))
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        Windows.ownTargets.insert(UInt32(window.windowNumber))
    }

    /// Shows what the camera sees right now, so you can tell whether a gesture registered.
    func update(frame: FrameResult, switcher: Switcher?, hasAccess: Bool) {
        guard window.isVisible, frame.time - lastUpdate >= 0.15 else { return }
        lastUpdate = frame.time
        let status: String
        if !hasAccess {
            status = "⚠️ Accessibility access is off, so gaze-switch can't switch or scroll. See the gaze-switch menu."
        } else if switcher == nil {
            status = "Calibrate first, from the gaze-switch menu."
        } else if let switcher, !switcher.enabled {
            status = "gaze-switch is off. Press \(model.hotkey) or hold up an open palm to turn it on."
        } else if switcher?.scrollSource == .hands {
            status = "🤏 Scrolling with your hand"
        } else if switcher?.scrollSource == .eyes {
            status = "👀 Scrolling with your eyes"
        } else if frame.face == nil {
            status = "Can't see your face. Sit where the camera can see you."
        } else if let hand = frame.hand, model.scrollMode.usesHands {
            switch HandGestureRecognizer.pose(of: hand) {
            case .pinch: status = "🤏 Pinch seen. Keep pinching and move your hand up or down."
            case .openPalm: status = "✋ Open palm. Hold it to turn gaze-switch on or off."
            case .other: status = "✋ Hand seen. Now pinch your thumb and index finger."
            }
        } else if model.scrollMode.usesHands {
            status = "Raise your hand to chin height so the camera can see it."
        } else if model.scrollMode.usesEyes {
            status = "Look at the shaded band at the top or bottom of this window."
        } else {
            status = "Scrolling is off. Pick Hands, Eyes or Both above."
        }
        if status != model.status { model.status = status }
    }
}

private struct TutorialView: View {
    @ObservedObject var model: TutorialModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        HStack(alignment: .top, spacing: 16) {
                            MethodCard(
                                title: "With your hand", symbol: "hand.pinch.fill", active: model.scrollMode.usesHands,
                                steps: [
                                    "Raise your hand to about chin height, so the camera can see it.",
                                    "Pinch your thumb and index finger together.",
                                    "Keep pinching and move your hand up or down, as if dragging the page.",
                                    "Let go to stop.",
                                ],
                                footnote: "Hold up an open palm for 1½ seconds to turn gaze-switch on or off."
                            )
                            MethodCard(
                                title: "With your eyes", symbol: "eye.fill", active: model.scrollMode.usesEyes,
                                steps: [
                                    "Look at the window you want to scroll.",
                                    "Look at its top edge to scroll up, or its bottom edge to scroll down.",
                                    "Hold your gaze there for about half a second. Closer to the edge scrolls faster.",
                                    "Look back toward the middle to stop.",
                                ],
                                footnote: "Works best with your face lit from the front."
                            )
                        }
                        practice
                    }
                    .padding(32)
                    .padding(.vertical, model.scrollMode.usesEyes ? geometry.size.height * model.eyeScrollEdge : 0)
                }
                if model.scrollMode.usesEyes { eyeBands(height: geometry.size.height * model.eyeScrollEdge) }
                VStack {
                    Spacer()
                    Text(model.status)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 14)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How to scroll").font(.largeTitle.bold())
            Text("gaze-switch scrolls whichever window you're looking at. Look at this window and try it here. It scrolls too.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Picker("Scroll with", selection: Binding(get: { model.scrollMode }, set: {
                model.scrollMode = $0
                model.onScrollModeChange($0)
            })) {
                ForEach(ScrollMode.allCases, id: \.self) { Text($0.rawValue.capitalized) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
        }
    }

    private var practice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Practice").font(.title2.bold())
            Text("Scroll down to the end of these rows.").foregroundStyle(.secondary)
            ForEach(1...30, id: \.self) { row in
                HStack {
                    Text("Row \(row)").font(.body.monospacedDigit().weight(.medium))
                    Spacer()
                    Text(row < 30 ? "keep going ↓" : "you made it 🎉").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.primary.opacity(row.isMultiple(of: 2) ? 0.04 : 0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            Text("Come back any time from the gaze-switch menu → How to Scroll.")
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
    }

    /// Marks where looking scrolls the window.
    private func eyeBands(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            band("Look here to scroll up ↑", height: height, fadeTo: .bottom)
            Spacer()
            band("Look here to scroll down ↓", height: height, fadeTo: .top)
        }
        .allowsHitTesting(false)
    }

    private func band(_ label: String, height: CGFloat, fadeTo edge: UnitPoint) -> some View {
        ZStack {
            LinearGradient(colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.06)],
                           startPoint: edge == .bottom ? .top : .bottom, endPoint: edge)
            Text(label).font(.headline).foregroundStyle(Color.accentColor)
        }
        .frame(height: height)
    }
}

private struct MethodCard: View {
    let title: String
    let symbol: String
    let active: Bool
    let steps: [String]
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 40))
                    .foregroundStyle(active ? Color.accentColor : Color.secondary)
                    .symbolEffect(.pulse, options: .repeating, isActive: active)
                Spacer()
                Text(active ? "On" : "Off")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(active ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.15), in: Capsule())
            }
            Text(title).font(.title2.bold())
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.callout.weight(.bold))
                        .frame(width: 22, height: 22)
                        .background(Color.accentColor.opacity(0.15), in: Circle())
                    Text(step).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(footnote).font(.callout).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        .opacity(active ? 1 : 0.6)
    }
}
