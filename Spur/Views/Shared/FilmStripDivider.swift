import SwiftUI

/// Panel divider styled after a 35 mm negative film strip.
///
/// A near-black vertical bar with small rounded "sprocket holes" running down
/// the centre, evoking the perforations between film frames.  Replace the
/// standard 1-pixel separator in multi-column layouts with this component.
struct FilmStripDivider: View {
    /// Number of sprocket holes to render.  Increase for taller windows.
    private let holeCount = 14

    var body: some View {
        ZStack {
            // Strip body — near-black in both modes for maximum film-negative drama.
            Rectangle()
                .fill(Color.black.opacity(0.88))

            // Sprocket holes
            VStack(spacing: 20) {
                ForEach(0..<holeCount, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(SpurColors.background.opacity(0.40))
                        .frame(width: 5, height: 4)
                }
            }
        }
        .frame(width: 10)
    }
}
