# Freeify: context index

A map of every critical module, so an agent loads only the files a task needs.
`CLAUDE.md` holds the rules and architecture; this file says **where things are**.

**Keep it current.** When a task adds, moves, renames, or changes what a module is
responsible for, update its entry here in the same commit, and add a line to
[Recent changes](#recent-changes). Refer to symbols, not line numbers; they drift.

## How to use this file

1. Find the task in [Task → files](#task--files) and load those files.
2. Check [Coupled changes](#coupled-changes): if you touch one side, load the other.
3. Use the [Module index](#module-index) for anything not listed; load a module's
   "depends on" files only when the change crosses into them.

## Task → files

| Task | Load |
|---|---|
| Library screen, sorting, search, multi-select, swipe actions, Add from Files | `LibraryView.swift`, `TrackRow.swift`, `LibraryStore.swift` |
| Song row look or its More menu | `TrackRow.swift`, then the screen that builds the menu |
| Liked Songs, playlists, Add to Playlist | `PlaylistViews.swift`, `LibraryStore.swift` (playlist methods), `Track.swift` (`Playlist`) |
| Download, re-download, Download All / Missing | `LibraryStore.swift`, `YouTubeSearch.swift` (`YouTubeSource.download`, `audioStream`), `Track.swift` (`AudioFiles`) |
| YouTube search tab, previews | `YouTubeSearch.swift` (`YouTubeSearchView`, `RemoteSongRows`, `PreviewPlayer`) |
| YouTube errors, "Login is required", bot checks | `YouTubeSearch.swift` (`YouTubeSource`), `YouTubeVisitorSession.swift`, `tools/youtube_tester/server.py`, ROADMAP.md §2 |
| Charts, new releases, moods, song radio | `YouTubeMusic.swift`, `DiscoverViews.swift` |
| Made for you mixes, taste, feedback | `Recommendations.swift`, `Ranker.swift`, `DiscoverViews.swift` (`MixView`) |
| Learned ranker, its Settings section | `Ranker.swift`, `Recommendations.swift` (`Recommender.features`), `SettingsView.swift` |
| Playback, queue, shuffle/repeat, lock screen, streams, gaps | `LocalPlayer.swift`, then `PlayerViews.swift` for UI |
| Player bar, Now Playing, queue view, playback alerts | `PlayerViews.swift`, `LocalPlayer.swift` (read its published state) |
| Volume matching | `LocalPlayer.swift` (`VolumeMatch`), `LibraryStore.lookUpLoudness`, `YouTubeSource.loudness` |
| Listening history, "Recently played" | `LibraryStore.attach`, `LocalPlayer` (`Listen`, `onListen`), `Track.swift` (`ListenEvent`), `DiscoverViews.swift` |
| Library data, models, storage location, migration | `Track.swift`, `FreeifyApp.swift` (`ModelContainer`, `LibraryRecovery`) |
| Tabs, navigation, "Playing from" | `FreeifyApp.swift` (`RootView`), `LibraryStore.swift` (`AppTab`, routes, `show`) |
| Settings, storage used, About | `SettingsView.swift`, `Track.swift` (`AudioFiles.usedBytes`) |
| Colors, shapes, motifs, button styles | `Theme.swift`, DESIGN.md |
| Build fails, IPA download | `.github/workflows/ios-build.yml`, `.claude/skills/freeify-build/` |
| Adding a Swift file | `tools/add_swift_file.py`, `Freeify.xcodeproj/project.pbxproj` |
| Install, refresh, Shortcut | README.md "How Freeify gets onto the phone" |

## Coupled changes

| If you change | Also change |
|---|---|
| A `@Model` (`Track`, `Playlist`, `ListenEvent`, `RecommendationEvent`) | Keep it auto-migratable (defaults/optionals); `FreeifyApp`'s schema list if a model is added |
| YouTube client values in `YouTubeSource` (user agent, client name/version, visitor source) | The `SYNC` block in `tools/youtube_tester/server.py` |
| `YouTubeVisitorSession` | `Tests/YouTubeVisitorSessionChecks.swift` (run by the workflow) |
| Ranking features (`Recommender.features`) | `RankingFeature`, `RankerWeights`, `Ranker.inputs`, Settings names (`Ranker` plain names) |
| A design token or motif | DESIGN.md, and ROADMAP.md §7 |
| A new Swift file | Register it: `python3 tools/add_swift_file.py Name.swift` from the repo root |
| Anything the user sees or does differently | README.md; ROADMAP.md status (`[ ] 🔨` until phone-checked) |
| A module's responsibility, a file added or moved | This file |

## Module index

### App shell

**`Freeify/FreeifyApp.swift`**: entry point.
- `FreeifyApp`: clears cookies; builds the `ModelContainer` at the fixed
  `Application Support/default.store` (`LibraryRecovery.storeURL`); falls back to an in-memory store with
  `libraryError` shown as an alert.
- `RootView`: the four tabs, the shared alerts, environment objects; on start attaches
  history, restores the last song, runs the paced loudness lookup.
- `withPlayerBar()` / `PlayerBarPlacement`: the mini player over every tab and bottom margins.
- `LibraryRecovery`: when the library has no songs, copies one that has songs from any
  reachable app group (the signed groups in `embedded.mobileprovision`, plus
  `group.<bundle ID>`); `report()` lists every library file with size and song count
  (read with SQLite, table `ZTRACK`) for Settings → Library files (temporary).
- Depends on: `LibraryStore`, `Track.swift` models, every tab view.

**`Freeify/LibraryStore.swift`**: song actions shared by every tab (`@MainActor`, one instance).
- Owns `player` (`LocalPlayer`) and `preview` (`PreviewPlayer`), download state
  (`downloadingTrackID`, `downloadingSongID`, `downloadProgress`, `bulkDownload`),
  `errorMessage`, navigation (`selectedTab`, `discoverPath`, `libraryPath`).
- Library: `add`, `remove`, `removeDownload`, `toggleLike`; playlists: `createPlaylist`,
  `add(_:to:)`, `remove(_:from:)`, `delete`.
- Downloads: `download`, `redownload`, `downloadAll`, `downloadMissing`, `cancelDownloadAll`.
- Playback entry points: `select` (library songs), `playRemote` (streamed lists), `togglePreview`.
- `lookUpLoudness`: older downloads, 30 s apart. `attach`: records `ListenEvent`s.
- Types: `AppTab`, `LibraryRoute`, `AppRoute`, `BulkDownload`.
- Depends on: `LocalPlayer`, `YouTubeSource`, `Track.swift`.

### Data

**`Freeify/Track.swift`**: SwiftData models and audio files.
- `Track` (title, artist, `filename`, `youtubeID`, `isDownloaded`, `likedAt`,
  `artworkFilename`, `remoteArtworkURL`, `loudness`), `Playlist` (ordered `trackIDs`),
  `ListenEvent` (one play).
- `SavedAudio`: `Sendable` result of an import or download.
- `AudioFiles`: the `Audio` folder, `usedBytes`, `importFile`, `saveDownload`,
  `saveArtwork`, `discard`; files are validated with `AVAudioPlayer` before use.
- `SongName.parse`: "Artist - Song" file names. `Artwork`: cover helpers.

### YouTube

**`Freeify/YouTubeSearch.swift`**: Search tab and all YouTube requests.
- `YouTubeSearchView`, `RemoteSongRows`/`RemoteSongRow` (shared by Discover lists).
- `PreviewPlayer`: stream-only previews.
- `SongResult`, `SongPage`: `Sendable` song values.
- `YouTubeSource` (caseless enum): `searchSongs`, `moreSongs`, `musicRequest`,
  `parseSong`, `download` (with `withTimeout`, 180 s), `audioStream` (visionOS client, AAC
  only), `watchPageVisitor` (playback visitor ID), `previewAsset`, `loudness`, `describe`
  (error messages with `Error code:`), JSON helpers `dig`/`text`.
- Depends on: YouTubeKit, `YouTubeVisitorSession`, `AudioFiles`.

**`Freeify/YouTubeMusic.swift`**: Discover's YouTube Music pages (extension of `YouTubeSource`).
- `radio(for:)`, `charts`, `newReleases`, `moods`, `playlists(for:)`, `songs(in:)`.
- `BrowseCard`, `MoodTile`. Items are collected anywhere on a page (`collect`) so small
  layout changes don't break rows.

**`Freeify/YouTubeVisitorSession.swift`**: `actor` sharing one visitor-ID lookup per
session; concurrent callers share it, cancellation of one doesn't cancel the rest.
Two instances: search/Discover and playback. Tested by `Tests/YouTubeVisitorSessionChecks.swift`.

### Playback

**`Freeify/LocalPlayer.swift`**: the playback engine (`@MainActor`).
- `PlayItem` (saved `Track` or streamed `SongResult`), `PlayContext` ("Playing from"),
  `Listen`, `RepeatMode`, `VolumeMatch` (−14 LUFS, turn-down only).
- Queue: `play(_:in:context:)`, `next`, `previous`, `playNext`, `addToQueue`,
  `moveUpNext`/`removeUpNext`, `moveUpcoming`/`removeUpcoming`, `toggleShuffle`,
  `cycleRepeat`, `forget` (before a track is deleted).
- Engines: `AVAudioPlayer` for files (`open`), `AVPlayer` for streams (`loadStream`,
  `attachStream`); `prepareNextIfNeeded` buffers the next stream in the last 45 s;
  `finishStreamAtListedLength`; `generation` drops late callbacks.
- System: `AVAudioSession` `.playback`, `updateNowPlaying`, `configureCommands`
  (lock screen), `handleInterruption`.
- Persists shuffle, repeat, last song and time in `UserDefaults` (`Saved` keys); `restore`.

**`Freeify/PlayerViews.swift`**: playback UI.
- `PlayerBar` (+ `ProgressStrip`), `RoundPlayButton`, `PlayItemArtwork`,
  `NowPlayingView` (Playing from, like/download, seek, controls), `PlaybackPosition`,
  `PlaybackButtons`, `QueueMenuItems`, `QueueView`, `PlaybackErrorAlerts`.

### Screens

**`Freeify/LibraryView.swift`**: Library tab: search, `LibrarySort`, song list with swipes
and More menu (`trackMenu`), multi-select, storage used, empty state, Add music menu, Files
import (`importAudio`), links to Liked Songs and Playlists.

**`Freeify/PlaylistViews.swift`**: `LikedSongsView`, `PlaylistsView`, `PlaylistDetailView`
(Download Missing), `PlaylistRouteView` (opens by ID), `SongPickerView`,
`AddToPlaylistView` (check marks, toggles), `PlaylistLabel`, `playlistName`.

**`Freeify/DiscoverViews.swift`**: Discover tab.
- `DiscoverView`: Recently played, Made for you, charts, new releases, moods; each row
  loads separately (`Loadable`); refreshes mixes on a new day.
- `MixView`, `CardSongsView`, `RadioView`, `MoodView`, `RemoteSongsScreen`,
  `DownloadAllButton`/`DownloadAllBanner`, `CardView`, `DiscoverSection`. `DiscoverRoute`.

**`Freeify/SettingsView.swift`**: Settings tab: storage, Match volume, Recommendations
(ranker status and weights, "Learn from my feedback"), About (version, logo, `EmptyStateMark`),
Library files (temporary `LibraryRecovery.report()` with Copy).

**`Freeify/TrackRow.swift`**: `TrackListRow` (row plus More button), `TrackRow` (cover,
title, artist, status chips, playing marker, Saved check), `ArtworkView`, `ArtworkPlaceholder`.

### Recommendations

**`Freeify/Recommendations.swift`**: rule-based "Made for you".
- `TasteProfile` (history, likes, saves; `affinity`, `seeds`), `Candidate`,
  `Recommender` (`features`, `rank` with per-artist limit and exploration slots),
  `Mix`, `RecommendationEvent` (`@Model`), `MadeForYou` (`mixes`, daily cache
  `made-for-you.json`, `record` feedback).

**`Freeify/Ranker.swift`**: milestone 6 logistic regression.
- `RankingFeature`, `RankerWeights` (hand-set defaults), `RankerStatus` (`ranker.json`),
  `Ranker`: `update` (train at refresh, use only if AUC beats hand-set), `examples`,
  `train`, `quality`, `inputs`.

### Design

**`Freeify/Theme.swift`**: every visual token and shape.
- `Palette`, `Spacing`, `Color` hex init.
- Shapes and motifs: `ArmorPanelShape`, `ArmorFacetShape`, `HairSlash`, `PlayHousing`,
  `PlayHousingSeams`, `ArmorBrackets`, `EmptyStateMark`, `ZigzagStrand`, `LooseArc`.
- Icons: `ThemeGlyph`, `GlyphView`, `SVGShape`.
- Components: `PrimaryActionStyle`, `StatusChip`, `SectionTitle`, `PlayingIndicator`.

### Outside the app

| Path | What it is |
|---|---|
| `Tests/YouTubeVisitorSessionChecks.swift` | Standalone checks for the visitor actor, compiled by the workflow |
| `.github/workflows/ios-build.yml` | Mac build: checks, session tests, unsigned IPA, artifacts kept 7 days |
| `.claude/skills/freeify-build/` | `/freeify-build`; `fetch_ipa.sh [commit]` waits for a build and saves the IPA on Windows |
| `tools/youtube_tester/server.py` | MCP server replaying Freeify's YouTube requests (`check_playback`, `ytdlp_compare`, …) |
| `tools/add_swift_file.py` | Registers new Swift files in the Xcode project |
| `Freeify/Info.plist`, `Freeify/Assets.xcassets`, `assets/` | App settings (audio background mode), icon, logo source |
| `CLAUDE.md`, `ROADMAP.md`, `DESIGN.md`, `README.md` | Rules, status, visuals, user how-to |

## Recent changes

Newest first. One line per finished task: what changed and which files. Trim entries
older than about a month once they're reflected in the index above.

- 2026-11-07: README rewritten: features by tab (four tabs, Settings added), then how
  Freeify gets onto the phone (build → Get Freeify Shortcut → SideStore, 7-day refresh,
  AltServer backup). Development details moved from README to CLAUDE.md "Build and dev
  tools". Docs only.
- 2026-11-01: Build #40's recovery found nothing (iloader install, library still empty).
  `LibraryRecovery` (`FreeifyApp.swift`) now tries the signed app groups and copies only a
  library that has songs; Settings → Library files shows where library files are
  (`SettingsView.swift`). **Waiting for the phone check** (install with iloader).
- 2026-11-01: Added `CLAUDE.md` and this file; moved the file helper to `tools/add_swift_file.py`.
- 2026-11-01: Library recovery from iloader's app group (`FreeifyApp.recoverAppGroupLibrary`),
  build #40. **Waiting for the phone check**: install with iloader once, then SideStore.
- 2026-11-01: Library store pinned to `Application Support/default.store` (`FreeifyApp`);
  SideStore install and "Get Freeify" Shortcut documented (README, build skill).
- 2026-10-29: Build skill and YouTube tester added; design motifs from the reference
  images (`Theme.swift`, `PlayerViews.swift`, `LibraryView.swift`, `SettingsView.swift`),
  waiting for the user's verdict.
- 2026-10-29: Playback visitor ID from the watch page (`YouTubeSearch.swift`), no cookies
  (`FreeifyApp.swift`), paced loudness lookups (`LibraryStore.swift`).
