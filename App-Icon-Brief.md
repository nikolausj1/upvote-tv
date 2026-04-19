# Creative Brief: Upvote TV — tvOS App Icon

## Context

Upvote TV is a personal, household-use tvOS app (plus iOS companion + Share Extension) that displays a shared queue of Reddit posts and YouTube videos to watch on the Apple TV. Family members capture links from their iPhones via the iOS share sheet; the tvOS app resolves metadata and presents the queue in a polished, "lean-back" living-room interface. It is **not** for App Store distribution — this is a private family app, installed via Xcode/TestFlight.

This brief is structured to be fed directly into an AI image generator. Four concepts are provided so the final direction can be chosen after seeing them rendered.

---

## Universal Requirements (apply to every variation)

**Format & composition**
- **Aspect ratio: 5:3 landscape** (tvOS home-screen icons are 400×240 pt; generate at 2560×1536 px for crispness).
- Strong, readable **silhouette from 10 feet away** — TV icons are viewed across a living room.
- Keep a ~10% safe margin around all edges; tvOS applies a subtle rounded-rectangle mask.
- Center the hero element; avoid putting detail in the corners.
- Design should work as a **single flat composition**. (It can be split into parallax layers afterward if desired.)

**Brand & content constraints**
- App name is **"Upvote TV"** — do **not** render the name as text on the icon (tvOS shows the label underneath). Icon is purely visual.
- **No Reddit branding, logos, mascots, or Reddit orange (#FF4500).** The app is source-agnostic.
- No YouTube logo or red-and-white play button either.
- No third-party trademarks of any kind.

**Aesthetic**
- Dark theme first. Deep background, luminous foreground.
- Premium, calm, Apple-native feel — adjacent to the Apple TV+, Music, Photos, and Fitness+ icons in spirit.
- Minimal. One clear idea per icon, not a collage.
- Subtle depth is fine (soft glow, gentle gradient, slight dimensionality). Avoid heavy skeuomorphism, stock textures, or cartoon shading.
- High contrast between foreground and background so the silhouette pops against any tvOS wallpaper.

**Symbolism guidance**
- The name "Upvote TV" suggests an **upward arrow / chevron** motif — a neutral, generic upvote glyph, not Reddit's.
- The "TV" half of the name invites screen / frame references, but don't be literal with a television bezel unless the concept calls for it.

---

## Variation 1 — "Luminous Upvote"

**One-line concept:** A single, confident upvote arrow rendered as a beam of warm light emerging from the bottom of the frame against a deep midnight backdrop.

**Visual elements**
- Hero: a large, bold, **rounded upvote chevron** (think a fatter, softer version of SF Symbol `arrow.up` or `chevron.up`) filling roughly 60% of the frame height, centered.
- The arrow looks like it's made of **soft emitted light** — warm gold fading to pale cream at the tip, with a gentle rim glow.
- Background: near-black radial gradient with a subtle cyan-to-indigo vignette; hint of atmospheric haze at the base of the arrow suggesting the light is projecting upward.
- No screen, no TV — purely symbolic. The arrow *is* the brand.

**Palette**
- Background: `#05070E` → `#0F1B2E` radial
- Arrow core: `#FFE8B0` → `#FFB347` gradient
- Accent glow: `#F2C76A` at 20% opacity

**Mood:** Premium, cinematic, confident. Reads as "elevated viewing."

**Sample prompt to feed the AI**
> A minimalist tvOS-style app icon at 5:3 landscape aspect ratio, 2560×1536. A single large soft upward-pointing chevron made of warm golden light (cream at the tip, amber at the base), centered on a deep near-black background with a faint cyan-to-indigo radial gradient. Subtle atmospheric haze rises from the arrow's base. Clean rounded silhouette, high contrast, premium Apple-TV feel. No text, no logos, no skeuomorphism. Flat composition, slight luminous glow.

---

## Variation 2 — "The Living Room Screen"

**One-line concept:** A softly glowing widescreen rectangle seen head-on, with an upvote chevron rendered as its content — like a TV whose picture *is* the idea of "up next."

**Visual elements**
- Hero: a rounded-corner **landscape rectangle** filling ~70% of the frame, centered, representing a screen without bezels.
- Inside the rectangle: a simple luminous upvote chevron, off-white, slightly inset so it feels projected onto the screen surface.
- The screen edge has a soft bloom / light-spill into the surrounding darkness (like a room lit only by the TV).
- Background: deep charcoal with the faintest warm color grade from the screen's light.
- Optional subtle scanline or film-grain *only if it doesn't cheapen the icon* — err toward none.

**Palette**
- Background: `#0B0B10` → `#15161C`
- Screen fill: deep teal-to-purple gradient `#1E2A44` → `#2D1A3F`
- Chevron: `#F7F5EE` with soft bloom

**Mood:** Cozy, cinematic, unmistakably "the TV in the living room at night."

**Sample prompt**
> A minimalist tvOS app icon at 5:3 landscape, 2560×1536. A softly glowing rounded-corner widescreen rectangle centered in the frame, representing a TV screen with no bezel. Inside the rectangle, a simple off-white upward chevron glyph, slightly inset and softly glowing. Deep teal-to-purple screen gradient. Dark charcoal background with a subtle warm light-spill at the screen edges, as if lighting a dark living room. No text, no logos, no Reddit orange. Premium Apple-TV aesthetic, cinematic, calm.

---

## Variation 3 — "Stacked Cards / Queue"

**One-line concept:** An overlapping stack of rounded content cards with the topmost card rising — literally visualizing "queue" and "upvote" together.

**Visual elements**
- Hero: three stacked **rounded-rectangle cards** (like playing-card shapes), slightly fanned, receding with perspective.
- The **top card is lifted upward** out of the stack, glowing at its edges as if selected/upvoted. Beneath it, an arrow-shaped shadow or subtle motion streak implies lift.
- Cards are abstract — no thumbnails, titles, or avatars on their faces. Each card has a faint inner gradient suggesting content without depicting it.
- Background: very dark neutral with a gentle directional light from top-left.

**Palette**
- Background: `#0A0C12`
- Back cards: `#1C2030`, `#242A3D` (cool grey-blues)
- Top/lifted card: a warmer accent `#2F3A5C` with a thin luminous outline in `#7FB8FF`

**Mood:** Clever, structural, editorial. Reads as "this is a curated queue."

**Sample prompt**
> A minimalist tvOS app icon at 5:3 landscape, 2560×1536. Three overlapping rounded-rectangle cards stacked with slight perspective, fanned downward. The top card lifts upward out of the stack, glowing at its edges with a cool blue rim light, as if selected or upvoted. A faint motion streak below hints at upward movement. Cards have subtle inner gradients but no visible content, text, or images. Dark neutral near-black background with a gentle top-left directional light. Clean Apple-TV aesthetic, editorial and premium.

---

## Variation 4 — "Constellation Chevron"

**One-line concept:** A large upvote chevron formed from a constellation of small glowing dots — each dot representing a piece of shared content, collectively forming the brand glyph.

**Visual elements**
- Hero: a **chevron/arrow-up silhouette made of ~40–60 small luminous dots** of varying sizes, centered, filling roughly 55% of the frame height.
- Dots have a soft bloom and vary slightly in brightness (a few are noticeably brighter — the "upvoted" ones).
- Faint curved connecting lines between nearby dots, very low opacity, suggesting a network / shared household.
- Background: deep space-navy with a subtle nebula-like color wash (not literal nebulae — just a soft gradient suggesting depth).

**Palette**
- Background: `#050915` → `#10162B`
- Dots: core `#F5F0DC`, bright accents `#FFD166`
- Connecting lines: `#8BA6D6` at 15% opacity

**Mood:** Shared, networked, collectible. Reads as "a collection of things worth watching."

**Sample prompt**
> A minimalist tvOS app icon at 5:3 landscape, 2560×1536. A large upward-pointing chevron silhouette formed from roughly 50 small glowing dots of varying sizes and brightness, centered in the frame. A few dots glow more brightly, like featured items. Faint, low-opacity curved lines connect nearby dots into a subtle network. Background is a deep navy with a very soft nebula-like color wash suggesting depth, not literal stars. Premium, calm, Apple-TV feel. No text, no logos.

---

## How to use this brief

1. Pick your image generator (Midjourney, DALL·E, Firefly, Ideogram, etc.).
2. Paste the "Sample prompt" block for the variation you want to try.
3. Always request a **5:3 (landscape)** aspect ratio. In Midjourney use `--ar 5:3`; in DALL·E request 2560×1536 or state the ratio explicitly.
4. Generate 2–4 candidates per variation and pick the strongest silhouette.
5. Once chosen, the final image can be split into parallax layers in Photoshop/Figma (background, middle, foreground) for Xcode's layered tvOS icon asset.

## Verification

- Drop the chosen PNG into `Upvote TV/Upvote TV/Assets.xcassets/App Icon & Top Shelf Image.brandassets/`.
- Build and run on the Apple TV simulator: `xcodebuild -scheme "Upvote TV" -destination 'platform=tvOS Simulator,name=Apple TV'`.
- Confirm the icon reads cleanly on the home screen at rest and when focused (tvOS enlarges + parallaxes focused icons).
- If the silhouette disappears against the tvOS wallpaper, push the background darker and the foreground glow brighter.
