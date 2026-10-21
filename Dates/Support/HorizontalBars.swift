import SwiftUI

extension View {
    /// Keeps a sheet's bars horizontal on iPhone Duo's outer display.
    ///
    /// Text buttons (Cancel, Save, Done) never move into the vertical bar, so in a sheet made
    /// only of them the vertical bar would hold nothing but the status bar and cost a strip of
    /// width. Apple's guidance names single- and text-button sheets as the case for opting out.
    @ViewBuilder
    func horizontalBarsOnly() -> some View {
        if #available(iOS 27.1, *) {
            toolbarVerticalBehavior(.disabled)
        } else {
            self
        }
    }
}
