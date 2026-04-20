import SwiftUI

/// Decorative header at the top of the Browse list.
///
/// Two visual layers:
/// 1. A soft cyan→magenta ambient glow occupying the top of the frame.
/// 2. An italic tagline picked from a fixed pool. The pool index is seeded by
///    the current calendar day, so the line is stable for an entire day and
///    rolls over at midnight without any persistence.
struct BrowseHeaderView: View {
    private let tagline: String

    init(date: Date = Date()) {
        self.tagline = Self.tagline(for: date)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ambientGlow
            Text(tagline)
                .font(.system(size: 64, weight: .light))
                .italic()
                .foregroundStyle(Color(white: 0.93))
                .padding(.leading, 8)
                .padding(.top, 40)
        }
        .frame(height: 240)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ambientGlow: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.27, green: 0.78, blue: 1.0).opacity(0.55),
                        .clear
                    ]),
                    center: UnitPoint(x: 0.22, y: -0.1),
                    startRadius: 0,
                    endRadius: geo.size.width * 0.45
                )
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.78, green: 0.35, blue: 1.0).opacity(0.5),
                        .clear
                    ]),
                    center: UnitPoint(x: 0.78, y: -0.1),
                    startRadius: 0,
                    endRadius: geo.size.width * 0.45
                )
            }
            .blur(radius: 40)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Tagline selection

    /// Returns the tagline for the given date. Stable within a single day,
    /// distinct between days, with no persistence required.
    static func tagline(for date: Date = Date()) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let seed = (comps.year ?? 0) * 366 + (comps.month ?? 0) * 31 + (comps.day ?? 0)
        return taglines[abs(seed) % taglines.count]
    }

    static let taglines: [String] = [
        // A. Tonight-framed
        "Tonight's lineup.",
        "Tonight's saved items.",
        "Tonight's short list.",
        "Tonight's picks.",
        "Tonight's reel.",
        "Tonight's queue.",
        "Tonight's rundown.",
        "Tonight's curated list.",
        "Tonight's selections.",
        "Tonight's roster.",
        "Tonight's program.",
        "Tonight's watchlist.",
        "Tonight's docket.",
        "Tonight's set.",
        "Tonight's slate.",
        // B. "Saved"-focused
        "Here's what you saved.",
        "Saved just for you.",
        "Saved for tonight.",
        "Saved for later.",
        "Set aside for you.",
        "Handpicked from the feed.",
        "What you set aside.",
        "Saved and ready.",
        "Saved this week.",
        "Your saved queue.",
        "Previously saved.",
        "What survived your scroll.",
        // C. Internet / feed framing
        "Best of the internet.",
        "Best of the feed.",
        "The internet's highlights.",
        "The good parts of the internet.",
        "The internet, edited.",
        "Today's feed, filtered.",
        "The internet, curated.",
        "The feed's finest.",
        "Feed highlights.",
        "From the web to the couch.",
        "Pulled from the feed.",
        "The feed, trimmed.",
        "Straight from the feed.",
        // D. Late-night / time-of-day
        "The late-night list.",
        "After-hours viewing.",
        "The nightcap list.",
        "Primetime.",
        "The evening's entries.",
        "For evening viewing.",
        "An evening's worth.",
        "The after-dark list.",
        "Nighttime programming.",
        "The evening slot.",
        // E. Queue-language
        "On deck.",
        "Queue's up.",
        "What's in the queue.",
        "Queued for tonight.",
        "Your queue, in full.",
        "Your watch pile.",
        "Your stack.",
        "The backlog.",
        // F. Compilation / gathered
        "Compiled today.",
        "Gathered for you.",
        "Assembled for tonight.",
        "Collected for viewing.",
        "From the household.",
        "Just the good ones.",
        "What made the cut.",
        "What's been saved up.",
        "A day's worth.",
        "Fresh from today.",
        // G. Miscellaneous curatorial
        "The household queue.",
        "A collection for tonight.",
        "Tonight's collection.",
        "Something for tonight.",
        "A short list for a long night."
    ]
}

#Preview {
    BrowseHeaderView()
        .background(Color.black)
        .frame(width: 1920, height: 300)
}
