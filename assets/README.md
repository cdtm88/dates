# Dates — brand asset suite

## iOS app icon
`AppIcon.appiconset/` — drop the folder straight into Xcode's Assets catalog. Contents.json declares
every required size (20/29/40/60/76/83.5pt at 1x-3x (filenames use -2x rather than @2x), plus the 1024 marketing icon).
`dark/` — the same size ladder in the dark tile treatment, for an iOS 18 dark appearance variant.

## Vectors
`svg/icon-light.svg`, `svg/icon-dark.svg` — 1024 tiles, gradient background baked in.
`svg/mark-light.svg` — mark only, transparent background (use inside the app UI).
`svg/mark-mono-light.svg`, `svg/mark-mono-dark.svg` — single-colour glyph for one-colour contexts.
`svg/lockup-horizontal-*.svg`, `svg/lockup-stacked-*.svg` — wordmark lockups. Text is live; convert to
outlines before sending anywhere without Instrument Sans installed.

## Raster extras
`mark-only-light-1024.png`, `mark-only-dark-1024.png` — 1024 mark on transparency.
`lockups/` — rendered PNG lockups at 3x.

## Specification
Grid: 100 units. Card inset 11, corner radius 15. Binding rings at x29 and x61, y7, 10x20, radius 5.
Card top band height 19. Flame apex at y42, base y63. Candle body 9x18 at y62. Mark occupies 62% of
the tile; tile corner radius 23%.

Colours — card #BF4400 / binding #8F3200 / candle #FF8324 / flame #FFD9B8,
light tile #FFF8F1 to #FFE6D2, dark tile #241A12 to #14181D. Dark variant: card #FF7A1C,
binding #C25200, flame #FFF3EA, candle #6B2600.

Wordmark: Instrument Sans Bold, tracking -3.8%. Clear space: one card-width on all sides.
Below 40pt the binding rings and top band are dropped and the flame merges with the wick — those
simplified tiers are already baked into the small PNGs in this suite.
