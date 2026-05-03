import WidgetKit
import SwiftUI

@main
struct ScoreWidgetBundle: WidgetBundle {
    // Trimmed to the 3 essentials. Per-sport drawn widgets were too unreliable
    // inside WidgetKit's runtime budget, especially when other apps are
    // foregrounded — the system starves the extension and they fall back to
    // the redacted/grey placeholder state. The universal LiveScoreWidget
    // already covers every sport via one fast scoreboard fetch.
    var body: some Widget {
        LiveScoreWidget()      // universal scores (every sport)
        PlayByPlayWidget()     // detailed feed for one game
        BracketWidget()        // NCAA tournament bracket
    }
}
