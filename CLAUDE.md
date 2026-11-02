# Freeify: working guide

The single source of truth for working on Freeify. Read it first, then `CONTEXT.md` to
find the files a task needs. When something here changes (stack, structure, rules, the
install route), update this file in the same commit.

| File | What it owns |
|---|---|
| `CLAUDE.md` | How to work here: stack, architecture, structure, patterns, rules |
| `CONTEXT.md` | Where things are: every module's job, task → files, coupled changes, recent changes |
| `ROADMAP.md` | What is built, phone-checked, or next; the YouTube-block playbook (§2) |
| `DESIGN.md` | Every visual decision: tokens, shapes, components, motion, accessibility |
| `README.md` | The user's how-to: features, building, installing, phone checks |

## Product

A personal iPhone music app: search YouTube Music, save songs on the phone, and play
them offline, including with the screen locked. One user, one phone; never released.

- **Everything runs on the phone.** No server, backend, account, or cloud sync, and none
  may be added to make a feature work.
- **The user has no Mac.** They work on Windows/WSL. Code is compiled only by GitHub
  Actions; nothing Swift can be compiled or run here.
- **The repo is public** (`gobrin111/freeify-`, branch `main`).

## Technical stack

| Layer | Choice |
|---|---|
| Language | Swift 5 language mode (`SWIFT_VERSION = 5.0`), the runner's default Xcode |
| Platform | iOS 17.0+, iPhone only (`TARGETED_DEVICE_FAMILY = 1`), dark mode only |
| UI | SwiftUI (`NavigationStack`, `TabView`, `@Query`, `@AppStorage`) |
| Library data | SwiftData: `Track`, `Playlist`, `ListenEvent`, `RecommendationEvent` |
| Playback | `AVAudioPlayer` for saved files, `AVPlayer` for streams and previews; `AVAudioSession` `.playback` with the `audio` background mode |
| Lock screen | MediaPlayer: `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter` |
| YouTube | [YouTubeKit](https://github.com/b5i/YouTubeKit), pinned to revision `6532af3`, plus hand-written YouTube Music web requests with `URLSession` |
| Recommendations | Plain Swift: rule-based mixes and an on-device logistic regression |
| Build | GitHub Actions on `macos-15`; an **unsigned** IPA, signed at install |
| Install | SideStore on the phone (the "Get Freeify" Shortcut); AltServer on Windows as backup |

YouTubeKit is the only dependency. Don't add another without a clear need and the
user's agreement.

## Architecture

```
FreeifyApp (ModelContainer at a fixed path)
└─ RootView: TabView (Library · Discover · Search · Settings), PlayerBar over every tab
   ├─ LibraryStore   @MainActor ObservableObject, one per app: song actions, downloads,
   │  │              navigation paths, errorMessage
   │  ├─ LocalPlayer   queue, shuffle/repeat, saved files and streams, lock screen,
   │  │                listening history (onListen), volume matching
   │  └─ PreviewPlayer search previews (stream only, never saved)
   ├─ YouTubeSource  caseless enum: every YouTube request (search, browse, download,
   │                 streams, loudness); two YouTubeVisitorSession actors
   └─ Recommender / MadeForYou / Ranker   Discover's mixes, on-device only
```

- **Views read, the store writes.** Screens read SwiftData with `@Query` and change data
  only through `LibraryStore` methods that take the view's `ModelContext`
  (`store.toggleLike(track, in: modelContext)`). The store saves and rolls back on failure.
- **Shared objects travel by environment**: `LibraryStore`, `LocalPlayer`, and
  `PreviewPlayer` are `@EnvironmentObject`s set once in `RootView`.
- **One download at a time**, tracked by the store (`downloadingTrackID`,
  `downloadingSongID`, `bulkDownload`).
- **Navigation is state.** `selectedTab`, `discoverPath`, and `libraryPath` live in the
  store so "Playing from …" can reopen a list (`AppRoute`, `DiscoverRoute`, `LibraryRoute`).
- **Theme is separate from logic.** Views take colors, spacing, and shapes from
  `Theme.swift`; downloads, storage, and playback never import design decisions.

### Where data lives (all inside the app's container)

| Data | Location |
|---|---|
| Library database | `Application Support/default.store`, a **fixed path** (see below) |
| Audio and cover art | `Application Support/Audio/<UUID>.m4a` / `.jpg` (`AudioFiles`) |
| Made for you cache | `Application Support/made-for-you.json` |
| Learned ranker | `Application Support/ranker.json` |
| Player state, settings | `UserDefaults`, keys like `player.shuffle`, `player.matchVolume` |

Audio files have random names. Titles, artists, likes, and playlists exist **only** in the
database, so losing the database loses the library even though the audio stays.

- **The store path is pinned on purpose.** SwiftData's default follows an app group when
  the signing tool adds one. iloader adds `group.<bundle ID>` and SideStore doesn't, so
  the library looked empty after switching tools. `FreeifyApp` opens the fixed path,
  shows an alert instead of an empty library if it can't, and `LibraryRecovery` copies a
  library with songs from any app group it can see when its own has none.
- **Model changes must migrate automatically.** There is no `VersionedSchema`; only add
  properties with defaults or optionals (as `Track.loudness` was). A failed migration
  shows the library-error alert.
- **Never delete the app to fix data problems:** saved audio lives inside it.

## Directory structure

```
freeify-/
├─ CLAUDE.md  CONTEXT.md  ROADMAP.md  DESIGN.md  README.md
├─ Freeify/                    the app; every Swift file is flat in this folder
│  ├─ FreeifyApp.swift         entry point, ModelContainer, RootView, player bar placement
│  ├─ LibraryStore.swift       song actions, downloads, Download All, routes
│  ├─ LocalPlayer.swift        playback engine, queue, lock screen, history, volume match
│  ├─ Track.swift              @Models Track/Playlist/ListenEvent, AudioFiles, SongName
│  ├─ YouTubeSearch.swift      Search tab, PreviewPlayer, YouTubeSource (requests)
│  ├─ YouTubeMusic.swift       YouTube Music browse: charts, releases, moods, radios
│  ├─ YouTubeVisitorSession.swift  actor sharing one visitor-ID lookup
│  ├─ Recommendations.swift    taste profile, candidates, Made for you, RecommendationEvent
│  ├─ Ranker.swift             learned ranker (features, training, AUC check)
│  ├─ DiscoverViews.swift      Discover tab and its lists
│  ├─ LibraryView.swift        Library tab
│  ├─ PlaylistViews.swift      Liked Songs, playlists, Add to Playlist
│  ├─ PlayerViews.swift        player bar, Now Playing, queue, playback alerts
│  ├─ TrackRow.swift           shared song row and artwork
│  ├─ SettingsView.swift       Settings tab
│  ├─ Theme.swift              design tokens, shapes, motifs, shared styles
│  ├─ Info.plist, Assets.xcassets
├─ Freeify.xcodeproj/          hand-maintained; register new files (see below)
├─ Tests/YouTubeVisitorSessionChecks.swift   compiled standalone by the workflow
├─ .github/workflows/ios-build.yml           the Mac build
├─ .claude/skills/freeify-build/             /freeify-build: wait for a build, fetch the IPA
├─ tools/youtube_tester/                     MCP server replaying Freeify's YouTube requests
├─ tools/add_swift_file.py                   registers new Swift files in the Xcode project
└─ assets/                                   logo source
```

Not in git: `build/` (local build output), `designReferences/`
(copyrighted screenshots; never commit them), `.agents/` (leave out of commits), `.venv/`.

- **New Swift files** go flat in `Freeify/` and must be added to the Xcode project:
  `python3 tools/add_swift_file.py Name.swift` from the repo root. Prefer adding to an
  existing file when the code belongs to it.
- **Don't restructure folders** without a clear need.

## Universal coding patterns

Match the surrounding code: its comment density, naming, and idiom.

- **Comments explain why**, in one or two plain sentences above a declaration, using the
  user's words ("Download All", "Playing from"). No doc-comment boilerplate, no commented-out code.
- **Namespaces are caseless enums** with static members: `YouTubeSource`, `AudioFiles`,
  `Ranker`, `MadeForYou`, `VolumeMatch`, `Palette`, `Spacing`.
- **UI state is `@MainActor`.** Stores are `final class … ObservableObject` with
  `@Published private(set)` state and methods to change it. Shared mutable state off the
  main actor is an `actor` (`YouTubeVisitorSession`).
- **Cross task boundaries with `Sendable` values, never models.** Downloads return
  `SavedAudio`/`SongResult`; the main actor turns them into `Track`s.
- **Late results are dropped.** Async work carries a generation number or ID, so a stale
  search page, preview, or stream can't replace a newer one; cancel obsolete tasks.
- **Errors reach the user as a plain sentence plus an `Error code:` line**
  (`YouTubeSource.describe`), set on `store.errorMessage`, `player.errorMessage`, or
  `preview.errorMessage` and shown as alerts by `RootView`. Never claim a song is saved
  before the file and database save both succeed; clean up files when a save fails.
- **Small helpers over layers.** A `static func` beside its use beats a new protocol,
  manager, or file. No speculative configuration.
- **Design comes from tokens.** Use `Palette`, `Spacing`, and `Theme.swift` shapes and
  styles (`PrimaryActionStyle`, `StatusChip`, `SectionTitle`, `TrackListRow`). No raw
  colors in screens; Reduce Motion, VoiceOver labels, and large text keep working.
  DESIGN.md decides anything visual.
- **Settings persist with `@AppStorage`/`UserDefaults`** under a `static let …Key` on the
  owning type. Small caches are `Codable` JSON in Application Support.

### YouTube rules

YouTube access is unofficial and breaks without warning.

- **Keep requests at a listening pace.** No bursts or loops over the library: an unpaced
  loudness pass likely caused the October 2026 "Login is required" block. Background
  lookups wait 30 seconds between songs.
- **Playback uses the youtube.com watch-page visitor ID** (`watchPageVisitor`) and the
  visionOS client; search and Discover use YouTube Music's visitor. Freeify keeps no cookies.
- **Client constants are mirrored** in `tools/youtube_tester/server.py` (its `SYNC`
  block). Change both together.
- **When playback breaks**, diagnose with the `freeify-youtube-tester` MCP tools first
  (calls few and spaced), then follow ROADMAP.md §2 "If YouTube blocks playback again" in order.

## Keeping context current

Every task ends by updating `CONTEXT.md`, in the same commit as the code:

- **A module's job changed, or a file was added, moved, renamed, or removed:** update its
  entry in the module index and any rows in "Task → files" and "Coupled changes".
- **Every finished task:** add one line at the top of "Recent changes" (date, what
  changed, which files, and whether it's waiting for a phone check).
- **Stack, architecture, structure, patterns, or rules changed:** update this file too.

Start each task by reading `CONTEXT.md` and loading the files it lists; widen only when
the change crosses into a module's dependencies. If the index is wrong, fix it.

## Working rules

From the user's `custom.md`:

- **Plan small.** Name the files to inspect and change, the checks, pass/fail criteria,
  and non-goals. Reuse existing patterns before creating new abstractions.
- **No over-engineering.** Choose the simplest solution that fully solves the current
  requirement, fits this architecture, and handles real edge cases. No new dependencies,
  folder moves, speculative infrastructure, unrelated features, broad cleanup, or
  future-proofing. Create planning documents only when useful or requested.

Project rules:

- **Commit and push only when the user says so.** End commit messages with the
  `Co-Authored-By` line. Never force-push. Leave `.agents/` and `designReferences/` out.
- **After pushing app code**, run `/freeify-build` (its `fetch_ipa.sh`) to follow the
  build, fix compile errors (at most two rounds before reporting), and fetch the IPA.
  Pushes that touch only docs start no build.
- **A green build is not a phone test.** Mark ROADMAP items `[x]` only after the user
  confirms on the phone; built-but-unchecked items are `[ ] 🔨`.
- **Never put passwords, tokens, cookies, or signing certificates in the repo.**
- **Don't expand build or install automation** unless asked.
- **Out of scope:** App Store release, servers or accounts, scanning the phone's files or
  Apple Music library, Last.fm or other outside recommendation services, crossfade.
