import SwiftUI

@Observable
final class PromptModel {
    var isVisible = false
    var deviceName = "AirPods"
    var isConnecting = false
    /// Set once the user presses anywhere on the pill; stops the auto-dismiss.
    var wasInteracted = false
    /// Mirrors the system Reduce Motion setting: no morph/slide, just a fade.
    var reduceMotion = false
    var onConnect: () -> Void = {}
    /// Height of the menu bar; the pill rests just below it.
    var topInset: CGFloat = 0
    /// Size of the physical notch on the current screen (height == 0 → no notch).
    var notchSize = CGSize.zero
    var hasNotch: Bool { notchSize.height > 0 }
}

/// The "Audio Detected" pill from the Figma design (node 3:27).
/// Morphs out of the notch (or the top edge) into a pill, and back again when dismissed.
struct AudioPromptView: View {
    /// Uniform scale applied to the Figma dimensions (1.0 = exact design size).
    static let scale: CGFloat = 1.2
    /// Size of the pill (the Figma frame).
    static let contentSize = CGSize(width: 328 * scale, height: 41 * scale)
    /// Gap between the menu bar and the pill.
    static let topGap: CGFloat = 8
    /// Transparent space around the pill for the shadow.
    static let shadowMargin: CGFloat = 40

    var model: PromptModel

    private var k: CGFloat { Self.scale }

    private static let airPodsImage: NSImage = {
        Bundle.module.url(forResource: "airpods", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) } ?? NSImage()
    }()

    private let captionGray = Color(red: 0x9B / 255, green: 0x9A / 255, blue: 0x9C / 255)

    // System accent color (follows System Settings; multicolor => system blue).
    private var accent: Color { Color(nsColor: .controlAccentColor) }
    /// Black or white label, whichever has more contrast on the current accent.
    private var labelOnAccent: Color { Self.prefersBlackLabel(on: .controlAccentColor) ? .black : .white }

    private static func prefersBlackLabel(on color: NSColor) -> Bool {
        guard let c = color.usingColorSpace(.sRGB) else { return true }
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let l = 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
        return (l + 0.05) / 0.05 >= 1.05 / (l + 0.05)   // contrast vs black >= contrast vs white
    }

    /// Starting shape: exactly the notch, or a small pill at the top edge.
    private var collapsedSize: CGSize {
        model.hasNotch ? model.notchSize : CGSize(width: 120 * k, height: 18 * k)
    }

    var body: some View {
        let visible = model.isVisible
        // With Reduce Motion the pill never morphs or moves; it just fades in place.
        let atRest = visible || model.reduceMotion
        let size = atRest ? Self.contentSize : collapsedSize
        let full = 28.8 * k
        // Native shape: its corner radii animate with everything else on the same spring.
        let top: CGFloat = atRest ? full : (model.hasNotch ? 0 : 9 * k)
        let bottom: CGFloat = atRest ? full : (model.hasNotch ? 10 : 9 * k)
        let shape = UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                           bottomTrailingRadius: bottom, topTrailingRadius: top,
                                           style: .continuous)

        ZStack {
            if visible {
                content
                    .frame(width: Self.contentSize.width, height: Self.contentSize.height)
                    // Content eases in on its own non-bouncy curve (as boring.notch does) so text
                    // doesn't overshoot past 100% scale while the shell springs.
                    .transition(model.reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .scale(scale: 0.9, anchor: .top))
                                    .animation(.smooth(duration: 0.35)))
            }
        }
        .frame(width: size.width, height: size.height)
        // Any press on the pill counts as interaction (doesn't interfere with the button).
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in model.wasInteracted = true })
        .background(.black, in: shape)
        .clipShape(shape)
        // Same as boring.notch: black @ 0.7, radius 6, no offset; clear when closed.
        .shadow(color: .black.opacity(visible ? 0.7 : 0), radius: 6)
        // Drops from the notch / top edge to its resting spot as it grows.
        .offset(y: atRest ? model.topInset + Self.topGap : 0)
        .opacity(model.reduceMotion && !visible ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var content: some View {
        HStack(spacing: 14.4 * k) {
            HStack(spacing: 7 * k) {
                Image(nsImage: Self.airPodsImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 23.04 * k, height: 23.04 * k)
                    .accessibilityHidden(true)   // decorative; the text says it all

                VStack(alignment: .leading, spacing: 0) {
                    Text("Audio Detected")
                        .font(.system(size: 8.64 * k, weight: .medium))
                        .foregroundStyle(captionGray)
                    Text(model.deviceName)
                        .font(.system(size: 11.52 * k, weight: .medium))
                        .foregroundStyle(.white)
                }
                .lineLimit(1)
                .fixedSize()
                .accessibilityElement(children: .combine)   // read as one phrase, e.g. "Audio Detected, <name>"
            }

            Spacer(minLength: 0)

            Button(action: model.onConnect) {
                // Keep the title in layout (hidden) so the button doesn't resize while the spinner shows.
                Text("Connect to this Mac")
                    .opacity(model.isConnecting ? 0 : 1)
                    .overlay {
                        if model.isConnecting {
                            ProgressView()
                                .controlSize(.small)
                                .environment(\.colorScheme, Self.prefersBlackLabel(on: .controlAccentColor) ? .light : .dark)   // match the label color
                        }
                    }
            }
            .buttonStyle(MacPushButtonStyle(fill: accent, textColor: labelOnAccent, fontSize: 11.52 * k, height: 29.6, hPadding: 30.96 * k))
            .accessibilityLabel(model.isConnecting ? "Connecting" : "Connect to this Mac")
            .disabled(model.isConnecting)
        }
        // Trailing inset matches the vertical margin so the button cap is concentric with the pill.
        .padding(.leading, 14 * k)
        .padding(.trailing, 9.8)
    }
}

/// Custom prominent push button that follows macOS control behavior:
/// darkens the fill while pressed (no scale/fade), dims when disabled,
/// and (via `Button`) fires on mouse-up inside the button.
private struct MacPushButtonStyle: ButtonStyle {
    let fill: Color
    let textColor: Color
    let fontSize: CGFloat
    let height: CGFloat
    let hPadding: CGFloat

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .medium))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .fixedSize()                      // hug the label instead of stretching
            .padding(.horizontal, hPadding)
            .frame(height: height)
            .background(fill, in: Capsule())
            .overlay(Capsule().fill(.black.opacity(configuration.isPressed ? 0.18 : 0)))
            .opacity(isEnabled ? 1 : 0.85)
            .contentShape(Capsule())
    }
}
