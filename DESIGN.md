# Freeify — Talia-inspired mobile design specification

## 1. Instructions for an AI implementation agent

Build Freeify, a personal offline music player for iPhone, using the visual system below. This file defines appearance and interaction, not the audio acquisition implementation. Apply it to the existing app architecture; do not replace working services just to restyle screens.

**Priority:** accessible music controls → readable library → character-inspired geometry → decorative detail.

MUST use the named tokens and component rules. MUST preserve conventional play, pause, search, download, and navigation meanings. SHOULD derive personality from silhouettes and material layering. MUST NOT turn the app into a busy game HUD.

Assume a character-inspired interface without full-screen character artwork. The uploaded references are the visual authority. “Talia” is the user's reference label; this document makes no claims about character canon. The palette is a deliberate UI adaptation of the images, not an exact color extraction.

Deliver reusable themed components, all documented states, and a working small-screen layout. Do not invent download progress or claim a track is saved before the storage layer confirms it.

## 2. Character-to-interface translation

| Observed reference feature | UI interpretation | Use location |
|---|---|---|
| Long pale pink, angular hair with sharp tapering ends | Pale pink accent; short tapered slash | Selected navigation, section markers, progress thumb detail |
| Uneven hair lengths and angular silhouette | One asymmetric clipped corner | Featured panel, primary action, player frame |
| Black jacket and layered graphite mechanical panels | Matte dark surfaces with restrained borders | Background, rows, sheets, mini player |
| Red-orange glove, collar, and mask accents | Warm action color | Primary play/download action |
| Cyan eye and mechanical light | Cool activity indicator | Active playback, downloading, focus |
| Pale yellow-green mask illumination in the dark reference | Small confirmation light | Saved/offline-ready status only |
| Segmented mask and forearm plates | Two or three offset geometric pieces | Download tray, queue icon, artwork corner brackets |
| Narrow curved strand above the hair | Single loose arc | Optional empty-state illustration only |
| Zigzag strand visible in the wider reference | Restrained tapered zigzag line, fading toward the tip | Optional empty-state accent; never text underline |

The visual character is expressive, angular, mechanical, and playful. Keep the content calm. No generic neon city backgrounds, random circuit boards, glitching labels, or dense fake diagnostics.

## 3. Color tokens

Use solid fills by default. Hex values are sRGB. Token names are semantic and must be shared across screens.

| Token | Hex | Required role |
|---|---|---|
| `color.bg.canvas` | `#101015` | Main app background |
| `color.bg.surface` | `#1B1B23` | Rows, panels, mini player |
| `color.bg.raised` | `#272630` | Sheets, menus, elevated controls |
| `color.bg.pressed` | `#35313E` | Pressed secondary surface |
| `color.border.subtle` | `#45404F` | Decorative separation, not sole control boundary |
| `color.border.control` | `#82798C` | Visible input and interactive outlines |
| `color.text.primary` | `#F6EDF2` | Titles and main text |
| `color.text.secondary` | `#BEB1C2` | Artist, duration, supporting labels |
| `color.text.muted` | `#96899D` | Noncritical metadata |
| `color.accent.hair` | `#E9B8D2` | Selected tabs, section accents, favorites |
| `color.accent.action` | `#FF715B` | Primary filled CTA and main playback control |
| `color.accent.activity` | `#71E5EA` | Progress, playing status, keyboard focus |
| `color.accent.ready` | `#DCEEA5` | Completed / available offline |
| `color.status.error` | `#FF939E` | Error text/icon and destructive actions |
| `color.ink.onAccent` | `#101015` | Text and glyphs on all bright accent fills |

Allocate roughly 80% of visible UI area to dark neutrals, 15% to text/artwork framing, and 5% to colored accents, excluding actual track artwork. Do not tint song thumbnails to fit the theme.

Use dark text on bright buttons, never white on the warm action fill. Borders that carry essential control information use `border.control`, not `border.subtle`. Do not rely on color alone: pair playing, saved, failure, and selection states with an icon or label.

The existing vivid multicolor Freeify logo remains the brand asset. Do not regenerate it, recolor it, or apply its rainbow gradient across the interface. Use it sparingly in About and optional onboarding. The character palette controls the app chrome.

## 4. Geometry and shape vocabulary

All measurements are logical points, not physical pixels. Reference width is 390 pt; layouts must adapt rather than scale a fixed screenshot.

### Armor panel

Create a reusable `ArmorPanelShape(cut: 10)` with a rectangular outline and a single clipped upper-right corner:

`(0,0) → (w-cut,0) → (w,cut) → (w,h) → (0,h) → close`

Default cut is 10 pt; 6 pt for compact chips, 12 pt for prominent artwork frames. Maximum cut is 15% of the shorter side. Use an internal 1 pt border. Keep content at least 16 pt away from panel edges and the clipped corner. Hit areas remain rectangular; do not make the clipped silhouette reduce tappable area.

Use on primary CTAs and featured player frames. Ordinary list rows remain simple rectangles with 8 pt image corners. Native sheets can retain their standard rounded top corners. Do not chamfer every surface.

### Hair slash

A small filled tapered quadrilateral based on the long pointed hair. At 24 × 24 local coordinates:

`M 14 3 L 19 3 L 10 21 L 7 21 Z`

Use in `accent.hair`, scaled to 4–6 pt wide and 16–20 pt high beside a selected item or heading. It is decorative, never a standalone navigation icon. One slash per selected item; no repeated spikes along the screen edge.

### Armor brackets

Use two short corner brackets outside the full rectangular artwork. Top-left local path: `M 0 14 L 0 0 L 14 0`; rotate for bottom-right. Stroke 2 pt; offset 6 pt from artwork. Use `border.control`, with one bracket becoming cyan during playback. Do not clip important artwork with decorative teeth or slashes.

### Mask-inspired playback control

Use an eight-sided housing for the large play button. On a 72 × 72 view box:

`M 18 0 H 54 L 72 18 V 54 L 54 72 H 18 L 0 54 V 18 Z`

Fill `accent.action`; central conventional play triangle uses `ink.onAccent`. No literal face or mask illustration. Pause replaces the triangle with two bars inside the same housing. At smaller sizes simplify to a circle or modest chamfered square.

## 5. Icon system

Use a 24 × 24 coordinate grid, 2 pt strokes, square or subtly rounded line caps, and bevel joins. Avoid long miter spikes. Maintain 2 pt optical padding. Standard glyph size is 22–24 pt inside a minimum 44 × 44 pt target. Toolbar glyphs do not need a surrounding filled tile.

Prefer existing system icons for standard actions. Use custom vector paths only for the small themed set below; keep each in a named reusable asset. Match visual weight across both types. Do not use emoji as interface icons.

| Action | Shape rule | Selected/active behavior |
|---|---|---|
| Library | Three vertical album spines; final spine has clipped upper corner | Pink stroke plus selection slash and label |
| Add music | Conventional plus within an open chamfered square | Warm fill for the main CTA; neutral in tab bar |
| Downloads | Down arrow into a tray with short angled ends | Cyan progress indicator; check on completion |
| Play | Standard right-facing triangle | Dark glyph on orange housing |
| Pause | Two equal vertical bars | Same housing and alignment as play |
| Previous / next | Standard triangle plus end bar | Neutral glyph, pressed surface on touch |
| Queue | Three stacked lines of unequal lengths with one clipped end | Cyan when the queue sheet is open |
| Favorite | Recognizable angular heart, softly beveled points | Pink filled heart; label/state announced |
| Search | Standard magnifying glass | Cyan focus outline on the input |
| More | Three horizontal dots | Raised surface on press |
| Delete | Standard trash bin | Error color inside a labeled menu action |
| Repeat / shuffle | Standard arrow forms | Pink plus explicit on-state marker |

Reference vector paths for custom icons, using `fill="none"`, `stroke="currentColor"`, `stroke-width="2"`, `stroke-linejoin="bevel"`:

```text
library:  M4 5H8V20H4Z M11 3H15V20H11Z M18 5H20L22 7V20H18Z
add:      M4 3H17L21 7V21H3V4Z M12 7V17 M7 12H17
download: M12 3V15 M7 10L12 15L17 10 M4 16V19L6 21H18L20 19V16
queue:    M4 6H18L20 8 M4 12H16L18 14 M4 18H12L14 20
```

These paths are starting geometry, not permission to distort recognizable actions. Inspect at actual 24 pt size. Keep text labels on the bottom navigation.

## 6. Typography and spacing

Use the platform system sans-serif. On iOS, use semantic text styles and Dynamic Type. Use monospaced digits only for elapsed time, total time, file sizes, and percentages. Do not use a sci-fi font for track names.

| Role | Default size / weight | Notes |
|---|---|---|
| Screen title | 28 / bold | Sentence case |
| Section title | 18 / semibold | Optional hair slash |
| Track title | 17 / medium | One line in compact rows; accessible expansion |
| Artist / body | 15 / regular | Secondary color |
| Button | 16 / semibold | Short verb label |
| Metadata | 13 / regular | Avoid for essential instructions |
| Player title | 24 / semibold | Up to two lines before scrolling/expanding |
| Time / download progress | 13 / medium, monospaced digits | Stable width |

Spacing scale: `4, 8, 12, 16, 24, 32, 48`. Screen gutter: 20 pt; compact widths may use 16 pt. Standard icon/text gap: 12 pt. Row vertical padding: 12 pt. Row minimum height: 72 pt. Album thumbnail: 48 × 48 pt. Increase row height for larger text rather than clipping.

Avoid all-caps paragraphs, excessive tracking, and fake terminal readouts. Functional labels should be plain language: “Library”, “Add music”, “Available offline”, “Retry”.

## 7. Reusable components and states

### Primary action

Minimum 48 pt high, horizontal padding 20 pt, single 8 pt corner cut. Warm fill and dark label. Icon optional. Press: scale to 0.98 and return; disabled: neutral raised fill and secondary label, no scale. Loading: spinner and a stable-width label; prevent duplicate submissions. Error details appear below the control.

### Track row

48 pt thumbnail left; title and artist center; duration and More button right. Main row tap plays. More is a separate target and must not also trigger playback. Currently playing: subtle raised fill, 3 pt pink leading marker, and small cyan playing glyph. Paused state uses a static pause glyph, not animated bars. Swipe actions may supplement but never replace the More menu.

### Mini player

64 pt minimum height above the bottom navigation and safe area. Dark raised surface with subtle border; 40 pt artwork, title/artist, play/pause target. A 2 pt cyan seek-progress strip along the top is informational, not a tiny scrub target. Tap the content area to open Now Playing; button taps only toggle playback. Long titles truncate cleanly. At accessibility text sizes allow a taller layout.

### Input field

48 pt minimum height, raised fill, 1 pt control border, 8 pt corner radius. Use URL-appropriate keyboard behavior for the source link. Focus: 2 pt cyan outline. Invalid: error icon and explanatory text, not border color alone. Keep paste and clear actions accessible.

### Status chip

Compact rectangular badge with one 6 pt clipped corner. Neutral fill, explicit icon and label. Downloading uses cyan; saved uses pale green; failed uses error pink. No status chip should appear to be a button unless it is actionable.

### Sheets and menus

Use native modal behavior, safe areas, dismiss gestures, and accessible focus order. Dark raised surface. Use normal labels and familiar icons. Reserve destructive color for “Delete downloaded track”. Removing from a playlist is a separate, nondestructive action.

## 8. Screen composition

### Library — default landing screen

1. “Library” title and Add music toolbar action.
2. Search field, followed by a labeled sort control.
3. Downloaded track list with source thumbnails.
4. Persistent mini player when a track is loaded.
5. Bottom navigation: Library, Downloads, Settings. Show labels. Add a Playlists tab only when playlist functionality is implemented.

No large decorative hero above the user's songs. Empty library: one small original abstract hair-slash/armor illustration, “Your music, ready offline”, and “Add music”. Search with no results: show “No matching tracks” and a clear-search action, not the first-run empty state.

### Add music — sheet or dedicated view

Link field → “Get track” → metadata preview → “Save offline”. The preview shows source thumbnail, editable title, optional artist, and available quality information. Download states are queued, downloading, finalizing, complete, canceled, failed. Only show numeric progress when the service supplies a reliable total; otherwise use an indeterminate indicator. Artwork failure must not block a successful audio save.

### Downloads

Rows include thumbnail or placeholder, title, status label, progress when known, cancel or retry. Completed items link to their library track. No permanent animated machinery. Offline state explains that new downloads need internet while saved tracks remain playable.

### Now Playing

Top: dismiss, “Now playing”, More. Center: large square source artwork with armor brackets, constrained by available height. Below: title, artist, favorite; seek slider with elapsed/remaining time; shuffle, previous, large octagonal play/pause, next, repeat; queue action. Use a familiar continuous slider, not a waveform unless real waveform data exists. Seek target height at least 44 pt even if the visible track is 4 pt.

On short screens, reduce artwork before shrinking controls. At large text sizes, let the content scroll. Support long titles and missing artist/artwork. Missing artwork uses a simple themed play/album placeholder, not a broken image icon.

### Settings

Plain grouped settings: storage usage, audio quality if supported, artwork options if supported, About. Show actual values from the app. Do not add speculative features as enabled switches.

### Later: library organization

Playlists reference tracks rather than duplicate files. Use the same rows and panel styling for playlist covers, metadata editing, favorites, and sort/filter sheets. Preserve the visual language rather than introducing a new style for each feature.

## 9. Motion and feedback

- Press response: 100–140 ms, gentle ease-out, maximum 2% scale change.
- Sheet transitions: use platform behavior; do not add a second competing animation.
- Selection changes: 160–200 ms color/position transition.
- Playing indicator: three small bars, 600–900 ms cycles, only while actually playing and visible.
- Download completion: one check transition, at most 240 ms; optional light haptic.
- Character energy comes from a crisp, slightly offset accent, not constant movement.
- Respect Reduce Motion: no scaling, pulsing, bouncing, or animated bars; use static state changes.
- Never flash or glitch content. Do not autoplay the supplied GIFs as backgrounds or UI decoration.

## 10. Accessibility and mobile behavior

Minimum touch target 44 × 44 pt; prefer 48 pt for major actions. Preserve device safe areas and keyboard avoidance. Controls need meaningful accessibility labels and selected/disabled states. Decorative slashes and brackets are hidden from screen readers. Playback position is an adjustable control with an announced value.

Verify at least 4.5:1 contrast for normal text, 3:1 for large text, and 3:1 for essential nontext control information on the actual background. Recheck any opacity changes and artwork overlays. Never place labels directly on arbitrary thumbnails without an opaque or sufficiently dark backing.

Support Dynamic Type, VoiceOver, Reduce Motion, and Increased Contrast. Do not use dim text as a stylistic substitute for hierarchy. Do not require swipe, long press, or color recognition for a core action.

Artwork is stored locally with tracks and displayed offline. The theme must not depend on remote fonts, remote decorative images, or network access. Loading and failure states must remain legible without artwork.

## 11. Implementation organization

Suggested files; adapt names to the existing stack:

- `Theme/ColorTokens`: one source for all semantic colors.
- `Theme/TypeTokens`: semantic typography and numeric formatting.
- `Theme/SpacingTokens`: spacing and dimensions.
- `Theme/Shapes`: ArmorPanel, HairSlash, ArmorBracket, PlayHousing.
- `Theme/Icons`: named custom vector assets and system icon mappings.
- `Components/TrackRow`, `MiniPlayer`, `PrimaryAction`, `StatusChip`, `ArtworkFrame`.
- Feature screens consume these components and existing playback/storage state.

No hardcoded accent values scattered throughout screens. Do not use screenshots of controls as assets. Draw the geometry with native paths or SVG where the existing framework supports it. Keep text and hit regions independent of decorative clipping. Keep theme styling separate from downloads, metadata storage, and playback logic.

## 12. Reference assets

The provided files guide visual interpretation; they are not required runtime assets:

- `designReferences/full-body.png`: full silhouette; the thin arc strand above the head, and the zigzag braid as sharp pink segments that narrow and fade toward the tip.
- `designReferences/face-closeup.png`: segmented dark mask with a red-orange cut, layered forearm plates, and the zigzag braid in motion.

Earlier references, not in the repository:

- `images.jpg`: warm-lit palette, pale angular hair, dark jacket, orange glove and collar details.
- `talia-from-cyber-punk-edge-runners-2-v0-40p8fm5vjwwh1.webp`: pointed hair, layered face geometry, cyan mechanical light.
- `talia-from-cyber-punk-edge-runners-2-v0-lzujpebvjwwh1.webp`: dark mechanical panels and pale green mask lights.
- `talia-from-cyber-punk-edge-runners-2-v0-sgf6sucvjwwh1.webp`: angular silhouette in near-darkness; do not imitate its low readability.
- `oucp3egvjwwh1.gif`: animated pose and energetic expression, inspected at several frames.
- `z064evlvjwwh1.gif`: wider silhouette, forearm segments, armor shapes, zigzag accent; supplied file contains one frame.

Do not infer additional character details or fetch replacement references. Do not include character screenshots in the app by default. If literal artwork is requested later, add it deliberately without putting it behind controls.

## 13. Acceptance checklist for the implementing AI

- [ ] The app reads as a music player immediately.
- [ ] Pink hair accents, orange actions, and cyan activity each have a consistent role.
- [ ] At least three specific character-derived motifs are implemented: hair slash, clipped armor panel, and octagonal play housing.
- [ ] Standard icons remain recognizable; navigation includes labels.
- [ ] Original Freeify brand logo is preserved and not used as a full-screen color scheme.
- [ ] Library, Add music, Downloads, Now Playing, and Settings share tokens/components.
- [ ] Empty, loading, offline, failed, disabled, selected, playing, and paused states are implemented where applicable.
- [ ] Saved music and its artwork work without network access.
- [ ] 320 pt, 390 pt, and 430 pt widths work without clipped controls or horizontal overflow.
- [ ] Long titles, missing artwork, large text, and keyboard presentation are checked.
- [ ] Contrast, touch targets, screen-reader labels, and Reduce Motion are verified.
- [ ] No gratuitous glows, glitch effects, character wallpaper, or fabricated progress.

When a feature is unspecified, choose the simplest accessible platform-native behavior, then apply these tokens. Do not improvise a second visual language.
