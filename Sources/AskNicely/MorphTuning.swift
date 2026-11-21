import CoreGraphics

/// Tuned numbers for the notch → droplet morph, read by `LiquidDropMorphView` and
/// `PromptPanelController`.
struct MorphTuning {
    static let shared = MorphTuning()

    // Timing
    let duration: CGFloat = 0.48       // seconds, entrance
    let exitDuration: CGFloat = 0.58   // seconds, exit (eased out, so it needs a bit longer to settle)
    /// Pacing: everything moves at an even speed except one smooth slow-down around the neck
    /// (swell → neck → pinch), so the drip has time to read. 0 = perfectly uniform.
    let neckSlowdown: CGFloat = 0.8    // how much slower the neck runs (0.8 ≈ 1.8× slower at its centre)
    let neckCenter: CGFloat = 0.38     // morph progress at the centre of the slow-down (the neck stretch + pinch)
    let neckWidth: CGFloat = 0.12      // spread of the slow-down, in morph progress

    // Shape
    let blendPeak: CGFloat = 26        // neck / fillet size at its widest
    let blendEnd: CGFloat = 6          // blend radius after the pinch (small → clean separation)
    let pinchStart: CGFloat = 0.30     // morph progress where the neck starts thinning
    let pinchEnd: CGFloat = 0.52       // morph progress where it has snapped
    let neckMarginStart: CGFloat = 20  // how thick the neck is as it starts thinning
    let neckMarginEnd: CGFloat = -6    // below 0 = separated (more negative = cleaner break)
    let dip: CGFloat = 12              // how far the drop falls past its resting spot
    let sag: CGFloat = 0               // how far the notch's bottom edge sags (0: the notch stays put)
    let dropStartWidth: CGFloat = 34   // width of the round drop
    let bloomStart: CGFloat = 0.35     // morph progress where the drop starts widening to the capsule
    let notchRadius: CGFloat = 16      // bottom corner radius of the notch body
    let skirt: CGFloat = 14            // how far the notch's whole bottom edge funnels down into the neck

    // Settle bounce (entrance only): the pill swells once on all sides and eases back, no rebound
    let bounceAmount: CGFloat = 0.025  // peak sideways scale-up (0.025 ≈ 6pt wider); 0 = none
    let bounceVertical: CGFloat = 0.35 // top/bottom move this fraction as much (≈ 0.4pt each)
    let bouncePeakTime: CGFloat = 0.12 // seconds from start to the biggest point
    let wobbleStart: CGFloat = 0.85    // fraction of the duration at which it starts (as the pill lands)
    /// Length of the settle clock in seconds (long enough for the bounce to die out).
    static let wobbleLength: CGFloat = 1.2
}
