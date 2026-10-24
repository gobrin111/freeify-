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

## 2. Online source feasibility (in progress)

Test whether a phone-only Swift integration can:

- [ ] Search the preferred catalog (YouTube) and return results that are mostly songs
- [ ] Download one track on the device
- [ ] Save it in `Application Support/Audio` and play it offline like an imported track

Test build: **Search YouTube** button in the library, using
[YouTubeKit](https://github.com/b5i/YouTubeKit) (b5i), pinned to commit `6532af3`.
It's not yet verified on the iPhone.
YouTube extraction is unofficial and may break. YouTube's official APIs do not
allow downloads. No server may be introduced to make this work.

**Done when:** one search, download, and offline play works on the iPhone. If it
can't be done, choose another source before starting milestone 3.

## 3. Search and download in the app

Starts only after milestone 2 succeeds.

- [ ] Search screen showing source results
- [ ] Result details (title, artist, duration)
- [ ] Download progress and clear error messages
- [ ] Downloaded tracks appear in the existing library and play offline

**Done when:** a song can be found, downloaded, and played offline entirely in Freeify.

## 4. Later, on request

Start these only when asked, or once milestones 1–3 work reliably:

- Queue and playlists
- Deleting tracks
- Visual polish

## Out of scope

- App Store release
- Servers, cloud sync, or accounts
- Scanning the phone's files or asking for access to the Apple Music library
- More build or install automation, unless requested
