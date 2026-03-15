import SwiftUI

/// Subtle static film-grain noise overlay evoking analogue photographic texture.
///
/// Apply as `.overlay(FilmGrainOverlay())` on any background panel.
/// The `.drawingGroup()` rasterises the canvas once into a GPU texture, so the
/// random dots don't regenerate on every view update.
struct FilmGrainOverlay: View {
    /// Grain opacity — keep below 0.12 to stay unobtrusive.
    var intensity: Double = 0.07

    var body: some View {
        Canvas { context, size in
            var rng = SystemRandomNumberGenerator()
            // ~8% pixel coverage gives visible texture without banding.
            let count = Int(size.width * size.height * 0.08)
            for _ in 0..<count {
                let x = CGFloat.random(in: 0..<size.width,  using: &rng)
                let y = CGFloat.random(in: 0..<size.height, using: &rng)
                context.fill(
                    Path(CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(.white.opacity(intensity))
                )
            }
        }
        .allowsHitTesting(false)
        .blendMode(.overlay)
        .drawingGroup()
    }
}
