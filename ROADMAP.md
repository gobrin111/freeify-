# Freeify roadmap

Freeify is a personal iPhone music app: search YouTube Music, save music for
offline listening, and keep playing with the screen locked. Everything runs on
the phone, with no server, cloud library, or backend to maintain.

A feature counts as done only after a successful GitHub Actions build and a check
on the iPhone. A local check on Windows does not count as an iPhone test.

**Status:** `[x]` checked on the phone · `[ ] 🔨` built, waiting for a phone check ·
`[ ]` not started

## 1. Local library foundation (done)

- [x] Import from Files into Freeify's own storage, with a SwiftData library
- [x] Imported tracks persist after relaunch and play in airplane mode
- [x] Audio continues with the screen locked, and lock-screen controls work
- [x] Invalid files show an error; files with the same name both stay playable
- [x] Library search matches partial titles and ignores capitalization
- [ ] Unplugging headphones pauses playback; interruptions are handled (deferred)

## 2. Online source feasibility (done)

- [x] Search from the phone, download a track, and play it offline
- [x] Playback takes its visitor ID from a youtube.com watch page, which fixed the
  October 2026 "Login is required" block (search and Discover keep YouTube Music's)
- [ ] 🔨 Background loudness lookups for older downloads wait 30 seconds between
  songs; the unpaced pass likely set off that block

Downloads use [YouTubeKit](https://github.com/b5i/YouTubeKit) (b5i), pinned to
commit `6532af3`, requesting formats as YouTube's visionOS client (the default iOS
client needs a proof-of-origin token). Playback sends the visitor ID from a
youtube.com watch page's config, the same source yt-dlp and InnerTubeX use; YouTube
Music's shorter browse visitor got "Login is required" on the phone. YouTube
extraction is unofficial and may break; if downloads break, check yt-dlp's current
client settings first. No server may be introduced to make this work.

### If YouTube blocks playback again

Try these in order. Each is `[ ]` until it is needed and then checked on the phone.

- [ ] **Diagnose first.** Compare against current yt-dlp from the PC on the same
  network (`--extractor-args "youtube:player_client=visionos"`). Test the phone on
  home Wi-Fi and on cellular with VPNs off. Check whether the phone uses IPv6
  (`api64.ipify.org` in Safari, Private Relay off); the PC is IPv4-only, and if
  only IPv6 is blocked, force IPv4 for YouTube requests
- [ ] **Show YouTube's reason** (`playabilityStatus.reason`) in the error popup;
  YouTubeKit drops it, so a "Login is required" can't be told apart from age limits
  or a region block
- [ ] **Optional sign-in** through a WebView, sending the account's cookies with
  playback requests. yt-dlp's maintainers recommend this for bot checks. It needs
  the "accounts" exclusion below lifted and risks flagging the Google account
- [ ] **TV client fallback, done properly.** The reverted attempt (`cd5cc6b`) could
  not work: TV formats come back ciphered. It needs yt-dlp's current TV client
  (`tv_samsung`), `signatureTimestamp` from the player script, and YouTubeKit's
  `deciphersURLs(player:)` for the signature and `n` parameter
- [ ] **Proof-of-origin tokens** from YouTube's BotGuard in a hidden `WKWebView`,
  with the web or mweb client. This fixes 403s on audio URLs, not "Login is
  required"; InnerTubeX uses it only for age-restricted and uploaded videos.
  Reference: [ytm-ios-probe](https://github.com/HCK5722/ytm-ios-probe)
  `PoTokenService.swift` and [InnerTubeX](https://github.com/MetrolistGroup/innertubex)
- [ ] **While blocked:** grey out songs that aren't saved, with one banner, rechecked
  at launch
- [ ] **Another source:** [Audius](https://docs.audius.co/) (free public API that
  allows streaming and downloads) after checking its catalog and terms; Jamendo
  needs a key entered in Settings

## 3. Search and download

- [x] YouTube Music Songs-tab search (real title, artist, and length, the way ytmusicapi does it)
- [x] Title and artist saved with downloads and shown in the library, player, and lock screen. Imports split "Artist - Song" file names
- [x] Download progress bar
- [x] Downloaded songs appear in the library and play offline
- [ ] 🔨 Preview a result before downloading: play/stop next to download, streamed without saving
- [ ] 🔨 Cover art in search results (not saved) and infinite scroll, 20 more songs per page
- [ ] 🔨 Clear error messages, with YouTubeKit's details in small print

## 4. Library and playback (Spotify-style)

### 4.1 Removing songs

- [x] **Remove download:** deletes the audio; the song stays listed as "Not downloaded" and downloads again with a tap
- [x] **Remove from library:** removes the song and its files
- [x] Songs from Files, and downloads made before video IDs were saved, offer only "Remove"
- [x] Removing the playing song stops playback cleanly
- [ ] 🔨 Songs already in the library show "In library" in search and can't be downloaded twice
- [ ] 🔨 Multi-select remove: More (…) → Select Songs
- [ ] 🔨 Storage used by saved songs, under the song list
- [ ] 🔨 Swipe buttons are text-only, so every row shows its labels

### 4.2 Playback queue

- [ ] 🔨 When a song ends, the next one from the same list plays, including with the screen locked
- [ ] 🔨 Next/previous in the app and on the lock screen; previous restarts a song more than ~3 seconds in
- [ ] 🔨 Shuffle (no repeats until every song has played) and repeat (off / all / one)
- [ ] 🔨 Songs that aren't downloaded are skipped

### 4.3 Playlists and Liked Songs

- [ ] 🔨 Create, rename, reorder, and delete playlists (delete by swiping in the Playlists list)
- [ ] 🔨 One song can be in many playlists without a second copy; removing a song from the library removes it from every playlist
- [ ] 🔨 Liked Songs: like from a swipe, long-press, or the full-screen player
- [ ] 🔨 Add to Playlist shows a check on playlists that already have the song; tapping toggles it in or out, and the sheet stays open until Done

### 4.4 Queue controls

- [ ] 🔨 "Play Next" and "Add to Queue" from a long-press; these play before the rest of the list
- [ ] 🔨 Queue view: see what's next, reorder it, and remove songs

### 4.5 Details and player

- [ ] 🔨 Cover art saved with new downloads and shown in lists, the player, and the lock screen
- [ ] 🔨 Sort the library by recently added, title, or artist
- [ ] 🔨 Compact player bar that opens a full-screen player with like and queue buttons; it has a close button that stops the music, and lists scroll clear of it
- [ ] 🔨 Shuffle, repeat, and the last song (paused where it stopped) are remembered after Freeify closes
- [ ] 🔨 Match volume (on by default, in Settings): louder songs are turned down to YouTube's -14 LUFS level using YouTube's loudness for each song, for saved songs, streams, and previews; older downloads get it looked up once in the background, 30 seconds apart

## 5. Discover

YouTube Music suggests candidate songs; Freeify decides which ones you'd like using
what you play on the phone. Each Discover row loads on its own, so a YouTube Music
page change breaks only that row. History and feedback never leave the phone.

### 5.1 Tabs and listening history

- [ ] 🔨 Three tabs: Discover, Search, and Library, with the player bar shared above them. YouTube Music search moves from a sheet into the Search tab
- [ ] 🔨 Save listening history on the phone: song, time, seconds listened, finished or skipped, and where it was played from (library, playlist, radio)
- [ ] 🔨 "Recently played" row in Discover

### 5.2 Song radio

- [ ] 🔨 "Start Radio" in the long-press menu of library songs from YouTube, search results, and Discover lists: similar songs with preview, download, and "In library"

### 5.3 YouTube Music rows

- [ ] 🔨 Charts: YouTube's chart playlists for your country
- [ ] 🔨 New releases
- [ ] 🔨 Moods & genres tiles that open playlists, then their songs

### 5.4 Made for you (rule-based)

- [ ] 🔨 Taste profile: artist and song scores from history (recent plays count more, finished songs and likes count extra, skips count against)
- [ ] 🔨 Seeds: your top songs and artists, rotated so mixes change
- [ ] 🔨 Candidates: radios from the seeds, minus songs already in the library
- [ ] 🔨 Ranker (rules): artist affinity, how many seeds suggested a song, at most 2 songs per artist per mix
- [ ] 🔨 Rows: "Mix from *song*" for three seeds and "Discover Mix" (artists you don't have yet), refreshed on the first visit after your local midnight (also when Freeify stays open overnight) or by pulling down, and saved for offline viewing
- [ ] 🔨 Feedback: record whether each recommendation was shown, previewed, downloaded, liked, or dismissed with "Not interested"

### 5.5 Playing Discover lists

- [ ] 🔨 Play buttons in mixes, charts, playlists, albums, and radios play in the player (bottom bar, lock screen, next/previous) with the list queued; songs not saved are streamed, saved songs play from their file. Search keeps previews
- [ ] 🔨 "Playing from …" in the full-screen player; tapping it opens where playback started: a Discover list, Recently played, Library, Liked Songs, or one of your playlists
- [ ] 🔨 Download All on those lists: saves the playlist first (songs not yet saved join the library as "Not downloaded"), then downloads them one at a time with progress and Cancel. The screen stays on meanwhile; a song that stalls for 3 minutes is skipped
- [ ] 🔨 Download Missing in a playlist's More (…) menu finishes an interrupted Download All
- [ ] 🔨 Shorter gaps between streamed songs: the next one is looked up and buffered in the current song's last 45 seconds, and a stall at a song's end moves on at once when the next is ready

**Done when:** Discover shows personal mixes that change with what you play, and
feedback is being recorded for milestone 6.

## 6. Learned recommendation ranker

Replaces only the `score` step of 5.4's ranker with a logistic regression learned from
your own feedback. Candidates still come from YouTube Music song radios, and everything
else in 5.4 (seeds, exclusions, at most 2 songs per artist, daily refresh) stays the
same. Training and scoring run on the phone in plain Swift: no libraries, no server,
and nothing new leaves the phone.

### 6.1 Record more features (start first, so data builds up)

- [ ] 🔨 Save more features with every recommendation event: song length, plus release year and YouTube play count where the song radio lists them, each scaled to a similar range, with a "missing" flag when a value isn't listed
- [ ] 🔨 Save each song's position in its mix, since songs near the top get more taps just for being there
- [ ] 🔨 Older events without the new features still train the weights they have

### 6.2 Labels

- [ ] 🔨 Liked or downloaded = yes (1); previewed = weak yes (1, half weight); "Not interested" = no (0); shown in a mix but never acted on by the next refresh = weak no (0, low weight)

### 6.3 The model

- [ ] 🔨 Logistic regression: chance you want a song = sigmoid(weights · features + bias); mixes are sorted by that chance, keeping the per-artist limits
- [ ] 🔨 Trained by gradient descent when the mixes refresh, with a penalty that keeps the weights close to today's hand-set ones (1.0, 0.6, 0.4), so with little data it behaves like 5.4 and moves only as evidence builds up
- [ ] 🔨 The learned weights are saved on the phone and survive restarts

### 6.4 Safety checks

- [ ] 🔨 Test on the newest 20% of events, which training never sees: use the learned weights only if they rank your yeses above your nos better than the hand-set weights do; otherwise keep the hand-set ones
- [ ] 🔨 Wait for enough data before switching on: at least ~200 events with ~30 yeses
- [ ] 🔨 Exploration: 2–3 slots per mix go to lower-ranked candidates, so the model doesn't narrow into a rut, and these slots are marked in the events
- [ ] 🔨 Settings shows the ranker in use (hand-set or learned), how many events it has learned from, and each weight in plain words, e.g. "Artist familiarity: 0.4 (was 1.0)", with a "Learn from my feedback" switch to go back to the hand-set weights

**Done when:** after a few weeks of real use, the learned ranker beats the hand-set
weights on the held-back events and runs the mixes, and Settings shows what it learned.

### 6.5 Understand the sound (after 6.1–6.4 work on the phone)

- [ ] Choose a small on-device audio model (e.g. one of Essentia's genre and mood models converted to Core ML) and check its size and speed on the phone
- [ ] Analyze saved songs once, in the background, and store their genre, mood, and energy
- [ ] Add "sounds like your saved songs" as a ranking feature for 6.3; candidates need a short streamed clip, which uses data
- [ ] Genre filter chips in the library from the same tags

## 7. Design (DESIGN.md)

- [ ] 🔨 Dark theme from DESIGN.md tokens: pink for selection and favorites, red for play and primary actions, cyan for playing and progress, pale green for saved
- [ ] 🔨 Character motifs: hair slash on section titles, armor-cut corner on primary buttons and mix covers, octagonal play button, armor brackets around Now Playing art
- [ ] 🔨 Song rows: 48 pt covers, playing marker and indicator, status chips, and a More button on every row
- [x] Motion: a one-time "Saved" check and light tap when a download completes, 180 ms fades for the current song and shuffle/repeat; all static with Reduce Motion
- [ ] 🔨 Optional motifs: loose arc and a hanging zigzag braid in the empty-library, no-match search, and Settings → About mark: a chain of filled diamonds that shrink and fade toward the tip, per both references
- [ ] 🔨 From the reference images: red action color (`#F5443A`, the gloves' red) for play and primary buttons, a lighter bevel facet at the clipped corner of primary buttons and raised panels (the faceted shoulder plates), and seams layering the octagonal play button (the segmented mask)
- [ ] 🔨 Mini player, Now Playing, queue, and Discover restyled; Library is the landing tab; Settings tab with storage and About
- [ ] Check on the phone: 320/390/430 pt widths, large text, VoiceOver, Reduce Motion

## Later, on request

- Share with testers without sideloading: TestFlight internal testing or an Ad Hoc build (needs the paid Apple Developer Program)
- Fix SideStore sign-in (`-80045`) so Freeify refreshes itself every 7 days

## Out of scope

- App Store release
- Servers, cloud sync, or accounts
- Scanning the phone's files or asking for access to the Apple Music library
- More build or install automation, unless requested
- Crossfade/gapless playback and playlist folders
- Last.fm or other outside recommendation services
