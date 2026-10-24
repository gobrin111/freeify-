# Freeify roadmap

Freeify is a personal iPhone music app: search a broad catalog, save music for
offline listening, and keep playing with the screen locked. Everything runs on
the phone, with no server, cloud library, or backend to maintain.

Each milestone passes only after a successful GitHub Actions build and a check
on the iPhone. A local check on Windows does not count as an iPhone test.

## 1. Local library foundation (done)

Built: import from Files into Freeify's own storage, SwiftData library, offline
playback, background audio, lock-screen controls, and library search.

Device checks (details in [README.md](README.md#first-device-checks)):

- [x] Imported audio plays on the phone
- [x] Imported tracks persist after relaunch
- [x] Playback works in airplane mode
- [x] Audio continues with the screen locked, and lock-screen controls work
- [ ] Unplugging headphones pauses playback; interruptions are handled (deferred, not tested yet)
- [x] Invalid files show an error; files with the same name both stay playable
- [x] "Search Freeify library" matches partial titles and ignores capitalization, shows "No matching songs" when nothing matches, and never lists files that weren't imported

## 2. Online source feasibility (done)

Test whether a phone-only Swift integration can:

- [x] Search the preferred catalog (YouTube) from the phone
- [ ] Results are mostly songs (currently plain YouTube results, including news and shorts; moved to milestone 3)
- [x] Download one track on the device
- [x] Save it in `Application Support/Audio` and play it offline like an imported track

Working on the iPhone: **Search YouTube** button in the library, using
[YouTubeKit](https://github.com/b5i/YouTubeKit) (b5i), pinned to commit `6532af3`.
Downloads request formats as YouTube's visionOS client (the default iOS client
needs a proof-of-origin token) and send the visitor ID from search (without it,
YouTube's bot check reports "Login is required"). If downloads break again, check
yt-dlp's current client settings first.
YouTube extraction is unofficial and may break. YouTube's official APIs do not
allow downloads. No server may be introduced to make this work.

**Done when:** one search, download, and offline play works on the iPhone. If it
can't be done, choose another source before starting milestone 3.

## 3. Search and download in the app

Starts only after milestone 2 succeeds.

- [x] Search screen showing source results
- [ ] Song-focused results: search YouTube Music's Songs tab (real title, artist, and length, the way ytmusicapi does it). Downloads still use YouTube via YouTubeKit (built, not yet checked on the phone)
- [ ] Result details: song title and artist split from YouTube titles ("Artist - Song (Official Audio)"), artist saved with downloads and shown in the library, player bar, and lock screen (built, not yet checked on the phone)
- [x] Download progress bar
- [ ] Same search returns consistent results: one visitor ID kept and sent with every search (built, not yet checked on the phone)
- [ ] Clear error messages (YouTubeKit errors currently show raw details)
- [x] Downloaded tracks appear in the existing library and play offline

**Done when:** a song can be found, downloaded, and played offline entirely in Freeify.

## 4. Library and playback (Spotify-style)

Build these in order. Each step builds on the ones before it.

### 4.1 Removing songs (in progress)

"Remove download" and "remove from library" are separate actions:

- [x] Save the YouTube video ID with each new download so it can be downloaded again
- [x] **Remove download:** delete the audio file to free space. The song stays in the library, marked "not downloaded", and can be downloaded again with one tap
- [x] **Remove from library:** remove the song and its file entirely (swipe to delete)
- [x] Songs imported from Files, and downloads made before video IDs were saved, can't be downloaded again. Offer only "Remove from library" for those
- [x] Removing the song that is playing stops playback cleanly
- [ ] Don't download a song that's already in the library: search shows "In library" (built, not yet checked on the phone)
- [ ] Multi-select remove (edit mode)
- [ ] Show storage used by downloads

**Done when:** both actions work on the phone. A removed download frees its space, and the song downloads again from the library.

### 4.2 Playback queue (built, not yet checked on the phone)

- [ ] When a song ends, play the next one from the list it was started from (library, search results, or playlist)
- [ ] Next/previous in the app and on the lock screen. Previous restarts the song when more than ~3 seconds in
- [ ] Shuffle: randomize the order once, so no song repeats until all have played. Turning it off returns to the original order
- [ ] Repeat: off / all / one
- [ ] Skip songs that aren't downloaded

**Done when:** a library plays through with the screen locked, using lock-screen next/previous, with shuffle and repeat working.

### 4.3 Playlists

- [ ] Create, rename, and delete playlists
- [ ] Add and remove songs (one song can be in many playlists without being stored twice), and reorder them
- [ ] Liked Songs: a heart on each song, plus a Liked Songs list
- [ ] Removing a song from the library removes it from every playlist. Removing only its download keeps it in playlists

**Done when:** playlists persist after relaunch and play through the queue.

### 4.4 Queue controls

- [ ] "Play next" and "Add to queue" from a swipe or long-press menu
- [ ] Queue view: see what's coming up, reorder it, and remove songs from it

### 4.5 Details and player

- [ ] Save the YouTube thumbnail with each download. Show it in lists and on the lock screen (artist is done in milestone 3)
- [ ] Sort the library by recently added, title, or artist
- [ ] Full-screen player (art, seek bar, shuffle/repeat). Opens by tapping the bottom bar

## Later, on request

- Remember shuffle/repeat and the last song after the app closes
- Visual polish

## Out of scope

- App Store release
- Servers, cloud sync, or accounts
- Scanning the phone's files or asking for access to the Apple Music library
- More build or install automation, unless requested
- Crossfade/gapless playback and playlist folders
