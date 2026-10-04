# Project icon source

Heap bundles Material Design Icons (MDI), `@mdi/font` release **7.4.47**, with **7,447 named icons**. It does not use Google's Material Icons catalog or download icons at runtime.

- Upstream repository: https://github.com/Templarian/MaterialDesign-Webfont
- Pinned distribution: https://registry.npmjs.org/@mdi/font/-/font-7.4.47.tgz
- `package/fonts/materialdesignicons-webfont.ttf` is copied unchanged to `heap-project-icons.ttf`. This replaces the previous 5-glyph subset; there is only 1 project icon font asset.
- `package/scss/_variables.scss` is copied unchanged to `ui/tool/mdi-7.4.47.scss`. Its complete name/codepoint table generates `ui/lib/mdi_glyphs.dart`.
- `package/LICENSE` is copied unchanged to `LICENSE.txt` (Pictogrammers Free License). The font/icons use Apache 2.0; the upstream license identifies non-font/non-icon code as MIT. `APACHE-2.0.txt` contains the full Apache license from https://www.apache.org/licenses/LICENSE-2.0.txt. Both license files are bundled as app assets.

SHA-256:

- npm archive: `66131558352dc8df724feac30f3b7bf7ee7311a79e4f8436f3637c0993edb773`
- full TTF: `61e8aba5a4e981fe22cf7c8e8bcdbea00476e75c62c37f01bf7ee33361d68428`
- upstream SCSS: `f0c474262836a8975ee5342e25b50a160f31be71281705ea4f4ac1cfc3bc555c`

Regenerate from the checked-in source, without network access:

```sh
cd ui
dart run tool/generate_mdi_catalog.dart
flutter test test/mdi_catalog_test.dart
```

The generated mapping uses const `IconData` values, not runtime integer-to-icon construction. Default Flutter icon tree-shaking retains every catalog entry used by the picker. Do not replace this map with dynamic `IconData` construction or the incompatible `material_design_icons_flutter` package.

Verification: default web and release APK builds retain all 7,447 named glyphs in their font cmap (1,056,428 bytes after tree-shaking); the debug APK retains the unchanged full font (1,307,660 bytes). Tests check the upstream table, full font cmap, and distinct rasterized glyphs outside the old subset (`airplane-takeoff`, `abacus`, `zodiac-virgo`). These checks do not replace browser/device visual review.
