# Heap icon proposals / issue #9

Barrett selected 01 / Teetering pile for issue #9. Sol-6.1 authored the artwork; Luna exported it for Android and web.

Start with [comparison.png](comparison.png). It shows all 3 drawings at 512px, square previews at actual 48/32px, and circle/squircle previews at 160px and actual 48/32px. View at 100% zoom to judge small sizes.

| Direction | Editable master | 1024px preview | Intent |
| --- | --- | --- | --- |
| 01 / Teetering pile | [SVG](01-teetering-pile.svg) | [PNG](01-teetering-pile.png) | Tall side-view silhouette; leaning layers and a blue note draped over the right shoulder. |
| 02 / Stepped mound | [SVG](02-stepped-mound.svg) | [PNG](02-stepped-mound.png) | Broad, uneven terraces in a low 3/4 view; loose sheets spill forward. |
| 03 / Curling heap | [SVG](03-curling-heap.svg) | [PNG](03-curling-heap.png) | Buckled sheets and open curls; the least orderly pile, with a blue note curling over the front-right edge. |

## Recommendation

I recommend 01 for the clearest answer to "how tall is the heap?" Its tapered silhouette reads as a pile rather than an overhead arrangement. Choose 03 if expressive, crumpled paper matters more than stacked height. 02 offers the broadest, calmest silhouette but makes height less obvious.

Tradeoffs: 01's layered base is more orderly than the reference. 03's upright curls can look flame-like at small sizes. All 3 lose handwriting, hatching and some edge separations at 32px, especially with the current 55% Android footprint. The blue note remains the main color cue. These are stylized vector drawings, not a perfect match for the original pencil marks.

## Provenance and editing

- New SVG path artwork authored for this proposal, inspired by `ui/web/icons/heap-512.png` and `~/Downloads/Chaotic paper heap with blue note.png`; neither source was altered.
- No image-generation API was available or used. Pencil grain comes from seeded SVG noise, subtle edge displacement, graphite speckling and drawn hatching. No external artwork, uploads, embedded raster images or new generator scripts.
- Masters use a 512-unit square viewBox and declare 1024px export dimensions. Named groups separate paper layers, the blue note, ground marks and artwork. Paths, fills and texture settings remain editable.
- Palette: warm cream background `#faf7f0`, ivory sheets `#fffaf0`, charcoal outlines `#282723`, cobalt note `#2478eb`; muted tan folds supply depth.
- PNGs were rendered locally with installed librsvg/Cairo libraries. The comparison was assembled with Pillow using inline shell commands; no rendering tool was added to the repo.
- Masks are review approximations, not Android exports. The transparent foreground, including ground marks, is trimmed and centered with its longest edge at 55% of mask width. The squircle uses an exponent-4 outline; real launchers vary.

## Export and verification

SVG XML and local references checked; all 3 PNG previews are 1024x1024, and the comparison is 1664x1192. Large and small previews were visually inspected. No application/device verification was performed at this artwork stage.

Regenerate production icons from the repository root:

```sh
python3 ui/tool/export_icons.py
```

The exporter requires Python 3, GdkPixbuf and librsvg with SVG filter support. On Ubuntu, install `libgdk-pixbuf-2.0-0` and `librsvg2-2`. It removes the SVG background for the transparent Android foreground and exports an opaque cream background. Web uses full-size artwork plus a separately padded maskable icon.

Barrett only needs the Android icon to fit his Pixel 6 Pro and chose to retain the current size rather than shrink it for other launcher masks. The 55% foreground footprint looked unclipped on the tested emulator, but it does not fit wholly inside Android's guaranteed 66dp safe circle on a 108dp layer. The exporter warns about that limitation without changing the chosen placement. The release APK was installed on Barrett's Pixel 6 Pro; both its home-screen and predicted-dock icons looked centered and unclipped, and tapping the home-screen icon opened Heap.

Flutter analysis, all 216 tests, debug/release APK builds and the web build passed. The release APK's circle launcher icon was visually checked on the API 37 emulator and Barrett's Pixel 6 Pro. Repeated exports reproduced all 11 production PNGs unchanged; native dimension, transparency and web maskable checks passed. This launcher work was only part of issue #9. The app's in-page mountain is now replaced with the same artwork; see `../heap-brand-refresh/README.md` for the in-app mark and applied Paper desk theme.
