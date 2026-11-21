import SwiftUI

@Observable
final class PromptModel {
    var isVisible = false
    /// Continuous 0 → 1 progress driving the water-droplet morph out of / back into the notch.
    var progress: CGFloat = 0
    /// Whether active-looking Liquid Glass can be forced (macOS 26+ and the private hooks exist).
    /// When `false` the pill simply stays notch-black.
    var glassAvailable = false
    var deviceName = "AirPods"
    var isConnecting = false
    /// Connection succeeded: the pill shows "Connected" + the battery ring before retracting.
    var isConnected = false
    /// AirPods battery (lowest bud), shown in the ring once connected. `nil` → unknown.
    var batteryPercent: Int?
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

/// The "Audio Detected" / "Connected" pill from the Figma design (nodes 8:28 and 8:18).
/// Morphs out of the notch like a Liquid Glass water droplet (bulging from the notch center,
/// stretching a liquid neck that pinches off, and settling into the capsule), and condenses
/// back into the notch when dismissed.
struct AudioPromptView: View {
    /// Uniform scale applied to the 319×66 Figma frame (~51.5pt tall, matching the original pill height).
    static let scale: CGFloat = 0.78
    /// Size of the pill at rest.
    static let contentSize = CGSize(width: round(319 * scale), height: round(66 * scale))
    /// Gap between the menu bar / notch and the resting pill.
    static let topGap: CGFloat = 10
    /// Transparent space around the pill for the shadow / metaball overscan.
    static let shadowMargin: CGFloat = 40

    var model: PromptModel
    @Environment(\.colorScheme) private var colorScheme

    private var k: CGFloat { Self.scale }

    private static let airPodsImage: NSImage = {
        Bundle.module.url(forResource: "airpods", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) } ?? NSImage()
    }()

    // Proportional dimensions from Figma nodes 8:28 / 8:18.
    private static let iconSize: CGFloat = 32 * scale      // Figma 8:30
    private static let iconInset: CGFloat = 4 * scale      // Figma 8:29 leading padding
    private static let circleSize: CGFloat = 42 * scale    // Figma 8:32 / 9:2
    private static let edgePadding: CGFloat = 12 * scale   // Figma frame padding

    var body: some View {
        let restingY = model.topInset + Self.topGap
        let dripEdgeY = model.hasNotch ? model.notchSize.height : 0

        Group {
            if model.reduceMotion {
                let shape = Capsule(style: .continuous)
                pillContent
                    .contentShape(shape)
                    .modifier(StaticSurfaceModifier(shape: shape, glassAvailable: model.glassAvailable))
                    .offset(y: restingY)
                    .opacity(model.isVisible ? 1 : 0)
                    .allowsHitTesting(model.isVisible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                LiquidDropMorphView(
                    progress: model.progress,
                    dripEdgeY: dripEdgeY,
                    restingY: restingY,
                    glassAvailable: model.glassAvailable,
                    isInteractive: model.isVisible,
                    content: pillContent
                )
            }
        }
        // On the black fallback, keep white/gray text regardless of the system appearance.
        .environment(\.colorScheme, model.glassAvailable ? colorScheme : .dark)
    }

    private var pillContent: some View {
        content
            .frame(width: Self.contentSize.width, height: Self.contentSize.height)
            // Any press on the pill counts as interaction (doesn't interfere with the button).
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in model.wasInteracted = true })
    }

    private var content: some View {
        HStack(spacing: 0) {
            Image(nsImage: Self.airPodsImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: Self.iconSize, height: Self.iconSize)
                .padding(.leading, Self.iconInset)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                .accessibilityHidden(true)   // decorative; the text says it all

            Spacer(minLength: 6)

            // Two centered lines: device name over status (Figma 8:28 / 8:18).
            VStack(spacing: 2.3 * k) {   // ≈ Figma's 19pt line height scaled
                Text(model.deviceName)
                    .font(.system(size: 14 * k, weight: .medium))
                    .foregroundStyle(.primary)
                Text(model.isConnected ? "Connected" : "Audio Detected")
                    .font(.system(size: 14 * k, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 6)

            ZStack {
                if model.isConnected {
                    BatteryRing(percent: model.batteryPercent, scale: k)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                } else {
                    connectButton
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .frame(width: Self.circleSize, height: Self.circleSize)
        }
        // 12pt scaled all round (Figma); keeps the trailing circle concentric with the capsule end.
        .padding(.horizontal, Self.edgePadding)
    }

    private var connectButton: some View {
        Button(action: model.onConnect) {
            ZStack {
                if model.isConnecting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "airplayaudio")
                        .font(.system(size: 20 * k, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: Self.circleSize, height: Self.circleSize)
        }
        .buttonStyle(CircleButtonStyle())
        .disabled(model.isConnecting)
        .help("Connect to this Mac")
        .accessibilityLabel(model.isConnecting ? "Connecting" : "Connect to this Mac")
    }
}

/// Translucent circular button (white @ 10%, Figma 8:32); brightens while pressed.
private struct CircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(.white.opacity(configuration.isPressed ? 0.2 : 0.1)))
            .contentShape(Circle())
    }
}

/// Battery ring shown after connecting (Figma 8:18): gray track, green arc, percentage inside.
/// Falls back to a checkmark when the battery level can't be read.
private struct BatteryRing: View {
    let percent: Int?
    let scale: CGFloat
    private var lineWidth: CGFloat { 4.5 * scale }   // Figma ring stroke

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: lineWidth)
            if let percent {
                Circle()
                    .trim(from: 0, to: CGFloat(max(0, min(percent, 100))) / 100)
                    .stroke(percent <= 20 ? Color.red : Color.green,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(percent)")
                    .font(.system(size: 14 * scale, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color(white: 0.72))
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 16 * scale, weight: .bold))
                    .foregroundStyle(.green)
            }
        }
        .padding(lineWidth / 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(percent.map { "Battery \($0) percent" } ?? "Connected")
    }
}

/// Static surface modifier used only when Reduce Motion is enabled.
private struct StaticSurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let glassAvailable: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), glassAvailable {
            content.glassEffect(.regular.interactive(), in: shape)
        } else {
            content
                .background(.black, in: shape)
                .clipShape(shape)
                .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        }
    }
}

/// Continuously morphs a Liquid Glass water droplet out of (and back into) the notch using
/// `GlassEffectContainer(spacing:)`'s GPU signed-distance-field smooth union across three elements:
/// 1. A wetting meniscus anchor tucked inside the bottom edge of the notch,
/// 2. An hourglass liquid neck stem that stretches across the gap below the notch and snaps/pinches off,
/// 3. The main droplet bulb that swells out of the notch center and blooms into the full capsule.
private struct LiquidDropMorphView<Content: View>: View, Animatable {
    var progress: CGFloat
    let dripEdgeY: CGFloat
    let restingY: CGFloat
    let glassAvailable: Bool
    let isInteractive: Bool
    let content: Content

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private func clamp(_ x: CGFloat, _ a: CGFloat = 0, _ b: CGFloat = 1) -> CGFloat {
        min(max(x, a), b)
    }

    private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = clamp((x - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }

    var body: some View {
        let p = clamp(progress, 0, 1)
        let overshoot = max(0, progress - 1)
        let targetW = AudioPromptView.contentSize.width
        let targetH = AudioPromptView.contentSize.height
        let shape = Capsule(style: .continuous)

        // Neck extension curve: extends to the notch rim as the droplet bulges out (p = 0.06..0.78),
        // then snaps back up inside the notch as the liquid neck pinches off (p = 0.64..0.88).
        let neckIn = smoothstep(0.06, 0.36, p)
        let neckOut = 1 - smoothstep(0.64, 0.88, p)
        let neck = neckIn * neckOut

        // 1. Notch wetting meniscus (always stays inside the notch at y_bottom <= dripEdgeY - 1,
        //    while its SDF blend field curves the shoulders of the emerging droplet into the notch).
        let anchorW: CGFloat = 56 + 48 * neck
        let anchorH: CGFloat = 14
        let anchorBottom: CGFloat = (dripEdgeY - 14) + 13 * neck

        // 2. Hourglass liquid neck stem bridging the notch rim and the top of the falling droplet.
        let stemW: CGFloat = 10 + 26 * neck
        let stemH: CGFloat = 8 + 15 * neck
        let stemBottom: CGFloat = (dripEdgeY - 14) + 19.5 * neck

        // 3. Main water droplet -> pill:
        // Surface tension holds the top near the notch initially while the bottom swells out,
        // then it accelerates through pinch-off and settles at restingY.
        let dropT = smoothstep(0.04, 0.94, p)
        let startTop = dripEdgeY - 28   // completely hidden inside the notch (or above screen top) at p = 0
        let heightT = smoothstep(0.02, 0.62, p)
        let baseH: CGFloat = 14 + (targetH - 14) * heightT

        // Stays a compact rounded water droplet bulb (56 -> 104pt, narrower than the notch) while
        // squeezing out of the notch, then blooms horizontally into the 249pt capsule as it detaches.
        let earlyW: CGFloat = 56 + 48 * smoothstep(0.0, 0.42, p)
        let bloomT = smoothstep(0.32, 0.98, p)
        let baseW: CGFloat = earlyW + (targetW - earlyW) * bloomT

        // Volume-conserving liquid squash & stretch when the spring overshoots at rest.
        let pillW = baseW + overshoot * 80
        let pillH = max(14, baseH - overshoot * 18)
        let pillTop = startTop + (restingY - startTop) * dropT + overshoot * 9

        let contentProgress = smoothstep(0.34, 0.92, p)

        Group {
            if #available(macOS 26.0, *), glassAvailable {
                GlassEffectContainer(spacing: 22) {
                    ZStack(alignment: .top) {
                        Color.clear
                            .frame(width: anchorW, height: anchorH)
                            .glassEffect(.regular.interactive(), in: shape)
                            .offset(y: anchorBottom - anchorH)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)

                        Color.clear
                            .frame(width: stemW, height: stemH)
                            .glassEffect(.regular.interactive(), in: shape)
                            .offset(y: stemBottom - stemH)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)

                        dropletPill(shape: shape, pillW: pillW, pillH: pillH, contentProgress: contentProgress)
                            .glassEffect(.regular.interactive(), in: shape)
                            .offset(y: pillTop)
                    }
                }
            } else {
                dropletPill(shape: shape, pillW: pillW, pillH: pillH, contentProgress: contentProgress)
                    .background(.black, in: shape)
                    .shadow(color: .black.opacity(0.45 * Double(p)), radius: 10, y: 4)
                    .offset(y: pillTop)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func dropletPill<S: Shape>(shape: S, pillW: CGFloat, pillH: CGFloat, contentProgress: CGFloat) -> some View {
        Color.clear
            .frame(width: pillW, height: pillH)
            .overlay {
                content
                    .scaleEffect(0.76 + 0.24 * contentProgress, anchor: .top)
                    .blur(radius: (1 - contentProgress) * 8)
                    .opacity(Double(contentProgress))
                    .allowsHitTesting(isInteractive)
            }
            .clipShape(shape)
            .contentShape(shape)
    }
}
