import CoreGraphics

/// Tuned numbers for the notch → droplet morph, read by `LiquidDropMorphView` and
/// `PromptPanelController`.
struct MorphTuning {
    static let shared = MorphTuning()

    // Timing
    let duration: CGFloat = 0.48       // seconds, show and hide
    /// 0 = perfectly uniform speed, 1 = the full pacing curve below (slow drip, quick elsewhere).
    let paceAmount: CGFloat = 0.1
    /// Pacing curve: sum of three smoothsteps (lead-in, drip, settle). Weights are fractions of morph
    /// progress; the settle weight is the remainder, so the three always add up to 1.
    let leadWeight: CGFloat = 0.2      // morph progress covered by the lead-in
    let dripWeight: CGFloat = 0.3      // morph progress covered by the drip (0.2 → 0.5)
    let leadEnd: CGFloat = 0.14        // time fraction where the lead-in ends
    let dripStart: CGFloat = 0.10
    let dripEnd: CGFloat = 0.50
    let settleStart: CGFloat = 0.40
    let settleEnd: CGFloat = 0.85
    var settleWeight: CGFloat { max(0, 1 - leadWeight - dripWeight) }

    // Shape
    let blendPeak: CGFloat = 26        // neck / fillet size at its widest
    let blendEnd: CGFloat = 6          // blend radius after the pinch (small → clean separation)
    let pinchStart: CGFloat = 0.28     // morph progress where the neck starts thinning
    let pinchEnd: CGFloat = 0.55       // morph progress where it has snapped
    let dip: CGFloat = 12              // how far the drop falls past its resting spot
    let sag: CGFloat = 0               // how far the notch's bottom edge sags (0: the notch stays put)
    let dropStartWidth: CGFloat = 34   // width of the round drop
    let bloomStart: CGFloat = 0.35     // morph progress where the drop starts widening to the capsule
    let notchRadius: CGFloat = 16      // bottom corner radius of the notch body

    // Settle wobble (entrance only)
    let wobbleAmount: CGFloat = 0.1    // 0 = none; 0.1 ≈ ±8pt wider / ±2pt flatter at the first squash
    let wobbleFrequency: CGFloat = 3   // oscillations per second
    let wobbleDecay: CGFloat = 7       // how quickly it dies down
    let wobbleStart: CGFloat = 0.6     // fraction of the duration at which it starts
    /// Length of the wobble clock in seconds (long enough for the decay to die out).
    static let wobbleLength: CGFloat = 0.9
}
