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

Downloads use [YouTubeKit](https://github.com/b5i/YouTubeKit) (b5i), pinned to
commit `6532af3`, requesting formats as YouTube's visionOS client (the default iOS
client needs a proof-of-origin token). Requests send a visitor ID from search
(without it, YouTube's bot check reports "Login is required"). YouTube extraction
is unofficial and may break; if downloads break, check yt-dlp's current client
settings first. No server may be introduced to make this work.

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

### 4.4 Queue controls

- [ ] 🔨 "Play Next" and "Add to Queue" from a long-press; these play before the rest of the list
- [ ] 🔨 Queue view: see what's next, reorder it, and remove songs

### 4.5 Details and player

- [ ] 🔨 Cover art saved with new downloads and shown in lists, the player, and the lock screen
- [ ] 🔨 Sort the library by recently added, title, or artist
- [ ] 🔨 Compact player bar that opens a full-screen player with like and queue buttons
- [ ] 🔨 Shuffle, repeat, and the last song (paused where it stopped) are remembered after Freeify closes

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
- [ ] 🔨 Rows: "Mix from *song*" for three seeds and "Discover Mix" (artists you don't have yet), refreshed daily or by pulling down, and saved for offline viewing
- [ ] 🔨 Feedback: record whether each recommendation was shown, previewed, downloaded, liked, or dismissed with "Not interested"

**Done when:** Discover shows personal mixes that change with what you play, and
feedback is being recorded for milestone 6.

## 6. Lightweight recommendation model (later)

Replaces only 5.4's ranker. It keeps the same inputs (taste profile, candidates,
feedback) and output (ranked songs), so nothing earlier changes. Start after a few
weeks of 5.4 feedback.

- [ ] Small learned ranker (logistic regression, kilobytes) trained on the phone from 5.4's feedback, using features like artist affinity, seed count, popularity, and length
- [ ] Optional: audio "sounds like" similarity (YAMNet or MusiCNN in Core ML, 3–15 MB) comparing candidates with downloaded songs. Candidates need a short streamed clip, which uses data
- [ ] Optional: genre tags (MusicBrainz lookup, or a model) for genre filter chips in the library and as a ranking feature

## Later, on request

- Share with testers without sideloading: TestFlight internal testing or an Ad Hoc build (needs the paid Apple Developer Program)
- Fix SideStore sign-in (`-80045`) so Freeify refreshes itself every 7 days
- Visual polish

## Out of scope

- App Store release
- Servers, cloud sync, or accounts
- Scanning the phone's files or asking for access to the Apple Music library
- More build or install automation, unless requested
- Crossfade/gapless playback and playlist folders
