import SwiftUI

@Observable
final class PromptModel {
    var isVisible = false
    /// Continuous 0 → 1 progress driving the water-droplet morph out of / back into the notch.
    var progress: CGFloat = 0
    /// 0 → 1 clock for the settle bounce at the end of the entrance (only animated on show).
    var wobblePhase: CGFloat = 0
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
                    wobblePhase: model.wobblePhase,
                    dripEdgeY: dripEdgeY,
                    notchWidth: model.hasNotch ? model.notchSize.width : 0,
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

/// One liquid body: the smooth union (polynomial smin of two signed-distance fields) of the notch
/// and a water droplet, traced row by row into closed outlines. While the two are joined it is one
/// piece with a neck between them; once they pinch apart each gets its own closed path.
private struct LiquidBlobShape: Shape {
    /// Notch body: centered, extends above the screen edge; only its bottom edge matters.
    var notchHalfWidth: CGFloat
    var notchBottom: CGFloat
    var notchRadius: CGFloat
    /// Droplet / pill: centered horizontally.
    var dropTop: CGFloat
    var dropWidth: CGFloat
    var dropHeight: CGFloat
    /// Smooth-union radius: how far apart the bodies can be and still merge (fillet / neck size).
    var blend: CGFloat
    /// How far the notch's whole bottom edge bulges down (bell-shaped: 0 at its corners, deepest in
    /// the middle), so the entire notch funnels into the neck rather than just its centre.
    var skirt: CGFloat = 0

    private static func roundBox(_ px: CGFloat, _ py: CGFloat, cy: CGFloat, hw: CGFloat, hh: CGFloat, r: CGFloat) -> CGFloat {
        let r = min(r, hw, hh)
        let qx = abs(px) - hw + r
        let qy = abs(py - cy) - hh + r
        return hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r
    }

    private func field(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
        let notchTop: CGFloat = -60
        var a = Self.roundBox(x, y, cy: (notchTop + notchBottom) / 2, hw: notchHalfWidth,
                              hh: (notchBottom - notchTop) / 2, r: notchRadius)
        if skirt > 0 {
            let u = min(abs(x) / notchHalfWidth, 1)
            a -= skirt * (1 - u * u) * (1 - u * u)
        }
        let b = Self.roundBox(x, y, cy: dropTop + dropHeight / 2, hw: dropWidth / 2,
                              hh: dropHeight / 2, r: dropHeight / 2)
        let h = max(blend - abs(a - b), 0) / blend
        return min(a, b) - h * h * blend / 4
    }

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        // Once the drop is farther from the notch than the blend radius, the smooth union no
        // longer changes it at all, so draw it as an exact capsule: the row-traced outline is
        // coarse on the capsule's shoulders, and the glass rim shows those kinks as a wiggle.
        // (Closest notch point is its centre, pushed down by the full skirt.)
        let gap = dropTop - (notchBottom + skirt)
        let dropIsExact = gap >= blend
        let traceBottom = dropIsExact ? notchBottom + skirt + 1 : max(dropTop + dropHeight, notchBottom) + 2
        let maxY = min(rect.maxY, traceBottom)
        var path = Path()
        var run: [CGPoint] = []
        // Closes the piece traced so far. Rows between separated bodies are empty, so each body
        // must be its own closed path (joining them would draw a diagonal wedge between them).
        func flush() {
            guard let first = run.first else { return }
            path.move(to: CGPoint(x: cx - first.x, y: first.y))
            path.addLine(to: CGPoint(x: cx + first.x, y: first.y))
            for pt in run { path.addLine(to: CGPoint(x: cx + pt.x, y: pt.y)) }
            for pt in run.reversed() { path.addLine(to: CGPoint(x: cx - pt.x, y: pt.y)) }
            path.closeSubpath()
            run.removeAll(keepingCapacity: true)
        }
        var y: CGFloat = 0
        while y <= maxY {
            if field(0, y) < 0 {
                var lo: CGFloat = 0, hi = rect.width / 2
                for _ in 0..<18 {
                    let mid = (lo + hi) / 2
                    if field(mid, y) < 0 { lo = mid } else { hi = mid }
                }
                run.append(CGPoint(x: lo, y: y))
            } else {
                flush()
            }
            y += 0.5
        }
        flush()
        if dropIsExact {
            let r = min(dropHeight, dropWidth) / 2   // matches the SDF's capsule (radius = half height)
            path.addRoundedRect(in: CGRect(x: cx - dropWidth / 2, y: dropTop, width: dropWidth, height: dropHeight),
                                cornerSize: CGSize(width: r, height: r), style: .circular)
        }
        return path
    }
}

/// Morphs the prompt out of (and back into) the notch as a single water droplet. One progress
/// value (0 → 1) drives everything: a drop swells out of the notch's bottom edge, hangs from a neck
/// that thins as surface tension lets go (the blend radius shrinks), pinches off as a round drop,
/// falls to its resting spot and widens into the capsule. Dismissal plays it in reverse.
private struct LiquidDropMorphView<Content: View>: View, Animatable {
    var progress: CGFloat
    var wobblePhase: CGFloat
    let dripEdgeY: CGFloat
    /// Width of the physical notch (0 → no notch; a small stand-in source is used).
    let notchWidth: CGFloat
    let restingY: CGFloat
    let glassAvailable: Bool
    let isInteractive: Bool
    let content: Content

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, wobblePhase) }
        set { progress = newValue.first; wobblePhase = newValue.second }
    }

    private func clamp(_ x: CGFloat, _ a: CGFloat = 0, _ b: CGFloat = 1) -> CGFloat {
        min(max(x, a), b)
    }

    private func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = clamp((x - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }

    /// Re-paces linear time `s` into morph progress with one smooth slow-down centred on the neck.
    /// Time spent per unit of progress is 1 + B·bell(progress) (a Gaussian bump at `neckCenter`), so
    /// the swell → neck → pinch lingers while everything else runs evenly, with no second burst.
    /// Elapsed time as a function of progress has a closed form (via erf); invert it by bisection.
    private func pace(_ s: CGFloat) -> CGFloat {
        let t = MorphTuning.shared
        let b = t.neckSlowdown, c = t.neckCenter, w = t.neckWidth
        guard b > 0 else { return s }
        let k = b * w * CGFloat.pi.squareRoot() / 2
        func time(_ q: CGFloat) -> CGFloat { q + k * (erf((q - c) / w) - erf(-c / w)) }
        let target = s * time(1)
        var lo: CGFloat = 0, hi: CGFloat = 1
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if time(mid) < target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    var body: some View {
        let t = MorphTuning.shared
        let p = pace(clamp(progress, 0, 1))
        // Settle bounce (entrance only, on its own clock): as the pill lands it swells once and eases
        // back, x·e^(1−x) with x = τ/peak: it starts moving outward immediately (continuing the
        // motion), peaks once and returns without rebounding. Mostly sideways; the top and bottom
        // move only `bounceVertical` as much. The content scales with the smaller (vertical) amount.
        let tau = wobblePhase * MorphTuning.wobbleLength
        let bx = tau / t.bouncePeakTime
        let bounce = t.bounceAmount * bx * exp(1 - bx)
        let bounceY = bounce * t.bounceVertical
        let overshoot = max(0, progress - 1)
        let targetW = AudioPromptView.contentSize.width
        let targetH = AudioPromptView.contentSize.height
        let nw = notchWidth > 0 ? notchWidth : 70

        // Notch body: sags a little as the drop pulls out, then lifts away once it has pinched off.
        let sag = smoothstep(0.05, 0.4, p) * (1 - smoothstep(0.5, 0.8, p)) * t.sag
        let lift = smoothstep(0.40, 0.75, p) * 34
        let notchBottom = dripEdgeY - 1 + sag - lift

        // Droplet: a round blob that falls from inside the notch, then widens into the capsule.
        let startTop = dripEdgeY - 17   // just inside the notch, so it starts emerging right away
        let dropT = smoothstep(0.0, 0.8, p)
        let dip = smoothstep(0.05, 0.5, p) * (1 - smoothstep(0.5, 0.95, p)) * t.dip
        // Starts short enough (14pt) to sit entirely inside the notch at p = 0, rounding out to 22pt.
        let baseH = max(14, 14 + 8 * smoothstep(0, 0.35, p) + (targetH - 22) * smoothstep(0.05, 0.9, p) - overshoot * 18)
        let dropH = baseH * (1 + bounceY)
        let dropW = (t.dropStartWidth + (targetW - t.dropStartWidth) * smoothstep(t.bloomStart, 1.0, p) + overshoot * 80)
            * (1 + bounce)
        let dropTop = startTop + (restingY - startTop) * dropT + dip + overshoot * 9 - baseH * bounceY / 2

        // The swell, funnel and merge radius all start at p = 0, so the bump under the notch grows
        // (and on the exit, shrinks) smoothly over the whole first stretch instead of vanishing a
        // tenth of the way before the end and leaving dead time.
        // Merge radius: tiny while the drop is still hidden (no bulge on the notch), wide as it swells
        // out, then shrinking so the neck thins until surface tension snaps it.
        // The notch's whole bottom edge funnels down toward the drop. It holds through the break and
        // then pulls back up smoothly, like the leftover liquid on a tap, so the notch doesn't snap
        // flat the instant the neck lets go (the fillet that formed most of the funnel vanishes then).
        let skirt = t.skirt * smoothstep(0, 0.34, p) * (1 - smoothstep(0.44, 0.66, p))
        // Merge radius. It first grows so the drop swells out of the notch with soft fillets. Then it
        // tracks the live gap between notch and drop: the smooth union joins two bodies while
        // gap < radius / 2, so radius = 2·gap + margin keeps them joined while margin > 0, and the
        // neck's thickness follows the margin. Shrinking the margin steadily over the pinch window
        // makes the neck stretch and thin at an even pace, however fast the drop is moving, instead
        // of snapping the moment the drop outruns a fixed radius. After the pinch it settles small.
        let rampUp = 4 + (t.blendPeak - 4) * smoothstep(0, 0.28, p)
        let gap = dropTop - (notchBottom + skirt)
        let margin = t.neckMarginStart - (t.neckMarginStart - t.neckMarginEnd) * smoothstep(t.pinchStart, t.pinchEnd, p)
        let tracked = max(4, 2 * gap + margin)
        let joined = rampUp + (tracked - rampUp) * smoothstep(0.24, 0.34, p)
        let blend = joined + (t.blendEnd - joined) * smoothstep(t.pinchEnd, t.pinchEnd + 0.12, p)

        let shape = LiquidBlobShape(
            notchHalfWidth: nw / 2, notchBottom: notchBottom, notchRadius: t.notchRadius,
            dropTop: dropTop, dropWidth: dropW, dropHeight: dropH, blend: blend, skirt: skirt)
        let contentProgress = smoothstep(0.55, 1.0, p)
        // Notch-black over the part of the body that overlaps / hangs from the real notch.
        let blackFade = 1 - smoothstep(0.35, 0.65, p)

        Group {
            if #available(macOS 26.0, *), glassAvailable {
                Color.clear
                    .overlay(alignment: .top) { notchBlack(opacity: blackFade) }
                    .overlay(alignment: .top) { pill(dropTop: dropTop, w: dropW, h: dropH, contentProgress: contentProgress, scale: 1 + bounceY) }
                    .clipShape(shape)
                    .glassEffect(.regular, in: shape)
                    .contentShape(shape)
            } else {
                Color.black
                    .overlay(alignment: .top) { pill(dropTop: dropTop, w: dropW, h: dropH, contentProgress: contentProgress, scale: 1 + bounceY) }
                    .clipShape(shape)
                    .shadow(color: .black.opacity(0.45 * Double(p)), radius: 10, y: 4)
                    .contentShape(shape)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Black down to the notch's bottom edge, fading to clear just below it, so the hanging drop
    /// emerges from the notch's black instead of starting as grey glass.
    private func notchBlack(opacity: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.black.frame(height: dripEdgeY + 2)   // always: the body never shows grey over the notch
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 18)
                .opacity(Double(opacity))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    private func pill(dropTop: CGFloat, w: CGFloat, h: CGFloat, contentProgress: CGFloat, scale: CGFloat) -> some View {
        content
            .scaleEffect(0.76 + 0.24 * contentProgress, anchor: .top)
            .scaleEffect(scale)
            .blur(radius: (1 - contentProgress) * 8)
            .opacity(Double(contentProgress))
            .allowsHitTesting(isInteractive)
            .frame(width: w, height: h)
            .offset(y: dropTop)
    }
}
