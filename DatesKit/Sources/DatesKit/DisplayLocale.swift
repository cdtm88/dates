import Foundation

extension Locale {
    /// The locale every displayed date is formatted in: the user's language, with the region
    /// they chose in Settings folded in.
    ///
    /// A region set apart from the language (English (US) with the UK region is
    /// `en_US@rg=gbzzzz`) is honoured by ICU only in patterns that include a year, so the
    /// same phone would show "3 December 1991" next to "December 3". Building the locale
    /// from the language and the region gives every pattern the region's order.
    public static func dateDisplay(from base: Locale = .current) -> Locale {
        guard let region = base.region else { return base }
        return Locale(languageCode: base.language.languageCode, script: base.language.script, languageRegion: region)
    }
}
