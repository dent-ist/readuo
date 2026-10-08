# Readuo logo assets

Source: user-supplied `C:/Users/realp/Downloads/readuo.svg`, preserved byte-for-byte as `readuo-original.svg`. Source SHA-256 is recorded in `generation-manifest.json`.

Regenerate from the repository's `qa` directory with `npm ci --ignore-scripts` then `node generate-brand-assets.mjs`. The generator requires the verified Arial Black font at `C:/Windows/Fonts/ariblk.ttf`, or `READUO_LOGO_FONT`. It checks both source and font hashes and refuses silent font substitution. The font binary is not redistributed. Outlined SVG derivatives have no runtime font dependency.

- Original PNG exports: 32, 48, 64, 96, 128, 192, 256, 400, 512 and 1024 pixels.
- Flutter login: original artwork at 64 pixels with 2x/3x/4x resolution variants. No theme, layout or navigation-glyph changes.
- Android legacy: original rounded artwork in all five launcher densities.
- Android adaptive: full-bleed source gradients with artwork scaled to 64%. Wordmark, sun and bars fit the 66dp safe circle; decorative book edges may follow the launcher mask. Background and foreground are separate density-specific resources.
- iOS: all existing AppIcon catalog sizes, opaque RGB PNGs. Original transparent margin and baked corner rounding are removed, with source gradients extended to square corners so the OS supplies its own mask. No iOS build or sign-in implementation is included.

The manifest records renderer versions, dimensions, alpha properties and output hashes. Two consecutive generations produced identical manifests. Preview mask images are under `app/test/artifacts/brand`; these simulations do not replace native Android launcher verification.
