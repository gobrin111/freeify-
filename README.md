# Freeify

A personal iPhone music app: search YouTube Music, save songs on the phone, and play
them offline, including with the screen locked. Everything runs on the phone: no
server, account, or cloud sync. Requires iOS 17 or newer.

What's built and what's been checked on the phone: [ROADMAP.md](ROADMAP.md).

## Features

Four tabs (Library, Discover, Search, Settings) with the player bar above every tab.

### Library (the landing tab)

- All your songs, with cover art, title, and artist; search by title or artist.
- Sort by recently added, title, or artist.
- **Liked Songs** and **Playlists** at the top. Create, rename, reorder, and delete
  playlists; a song can be in many playlists without a second copy.
- Swipe right or long-press to like a song or add it to a playlist.
- Swipe left to **Remove Download** (the song stays listed and downloads again with a
  tap) or **Remove** it from the library entirely.
- **Select Songs** in the More (…) menu to remove several at once.
- **Add music → Add from Files** copies an audio file into Freeify. Freeify never scans
  the phone's files.
- Storage used by saved songs, under the list.

### Search

- YouTube Music's Songs search, with cover art and more results as you scroll.
- **Preview** streams a song without saving it; **Download** saves it with its cover
  art. Songs you already have show "In library".
- Long-press a result for **Start Radio** (similar songs).

### Discover

- **Recently played**.
- **Made for you**: "Mix from *song*" and "Discover Mix", built on the phone from what
  you play, like, skip, and save. They refresh each day or when you pull down, and can
  still be viewed offline. Long-press → **Not Interested** removes a song.
- YouTube Music **charts**, **new releases**, and **moods & genres**.
- Play buttons stream songs that aren't saved. **Download All** saves a list as a
  playlist and downloads its songs one at a time, with progress and Cancel;
  **Download Missing** in a playlist's More (…) menu finishes an interrupted one.

### Playback

- The list a song is played from becomes the queue. Songs that aren't saved are
  skipped in library lists and streamed in Discover lists.
- Next/previous, shuffle (no repeats until every song has played), and repeat
  (off / all / one), in the app and on the lock screen.
- Long-press a song for **Play Next** or **Add to Queue**; the queue view reorders and
  removes songs.
- Tap the player bar for the full-screen player: like, download, seek, queue, and
  **Playing from …**, which reopens the list playback started from.
- Plays with the screen locked and in airplane mode (saved songs).
- Shuffle, repeat, and the last song (paused where it stopped) are remembered.

### Settings

- Storage used.
- **Match volume** (on by default): turns louder songs down to the same level using
  YouTube's loudness for each song.
- **Recommendations**: which ranker is in use, what it has learned, and a
  **Learn from my feedback** switch.
- About, and **Library files** (temporary: where the library database is, for
  diagnosing an empty library).

### Privacy

Listening history, likes, and recommendation feedback stay on the phone. Freeify never
signs in to YouTube and keeps no cookies.

## How Freeify gets onto the phone

There's no Mac and no App Store. The app is compiled on GitHub's Mac, then installed and
signed on the phone by SideStore with your free Apple ID.

```
push to main ─▶ GitHub Actions builds an unsigned IPA (kept 7 days)
             ─▶ "Get Freeify" Shortcut on the iPhone downloads it
             ─▶ SideStore signs and installs it (LocalDevVPN on)
             ─▶ SideStore refreshes it before 7 days run out
```

### Every new version

1. A push to `main` that changes the app starts a build automatically
   ([Actions tab](https://github.com/gobrin111/freeify-/actions)). Wait for the green check.
2. On the iPhone, turn on **LocalDevVPN**.
3. Run the **Get Freeify** Shortcut, pick **SideStore** in the share sheet, and confirm.
   If SideStore isn't offered, open SideStore → **My Apps → +** and pick
   `On My iPhone/Freeify/Freeify-unsigned.ipa`.

Updating keeps your library and saved songs.

### Every seven days

Free Apple ID apps expire after seven days. Turn on LocalDevVPN and tap **Refresh All**
in SideStore's **My Apps** before then. If the app does expire, the saved songs are still
inside it; refresh or reinstall to open it again.

### One-time setup

1. Install **LocalDevVPN** from the App Store.
2. Install SideStore from the PC with
   [iloader](https://docs.sidestore.io/docs/installation/prerequisites) and sign in to
   SideStore with your Apple ID. If sign-in fails with -80045, set SideStore's anisette
   server to **SideStore (New)** and reset adi.pb; don't retry repeatedly. A free Apple
   ID allows three sideloaded apps, SideStore included.
3. Create the **Get Freeify** Shortcut (below).

#### The "Get Freeify" Shortcut

GitHub requires a sign-in to download builds, so the Shortcut carries a read-only token:

1. On github.com: **Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token**. Name it `Freeify Shortcut`, choose
   **Only select repositories → freeify-**, and under Repository permissions set
   **Actions: Read-only**. Copy the token. It lives only in the Shortcut, never in the
   repository, and can do nothing but read builds.
2. In the Shortcuts app, create a shortcut named **Get Freeify** with these actions:

| # | Action | Settings |
|---|---|---|
| 1 | **Text** | the token (rename the output `Token`) |
| 2 | **Get Contents of URL** | `https://api.github.com/repos/gobrin111/freeify-/actions/workflows/ios-build.yml/runs?branch=main&status=success&per_page=1`; Headers: `Authorization` = `Bearer ` + Token, `Accept` = `application/vnd.github+json` |
| 3 | **Get Dictionary Value** | `workflow_runs` |
| 4 | **Get Item from List** | First Item (rename `Run`) |
| 5 | **Get Dictionary Value** | `run_number` in Run (rename `Number`) |
| 6 | **Get Dictionary Value** | `artifacts_url` in Run |
| 7 | **Text** | Dictionary Value + `?name=Freeify-unsigned-` + Number |
| 8 | **Get Contents of URL** | Text; the same two headers |
| 9 | **Get Dictionary Value** | `artifacts` |
| 10 | **Get Item from List** | First Item |
| 11 | **Get Dictionary Value** | `archive_download_url` |
| 12 | **Get Contents of URL** | Dictionary Value; header `Authorization` = `Bearer ` + Token only |
| 13 | **Extract Archive** | Contents of URL (gives `Freeify-unsigned.ipa`) |
| 14 | **Save File** | to `On My iPhone/Freeify`; Ask Where to Save off, Overwrite on |
| 15 | **Share** | Extracted file, then pick **SideStore** |

If step 12 returns a short XML or 401 error instead of a zip, report it rather than
retrying. If no build has run in seven days, start one (Actions tab → **Build Freeify
for iPhone → Run workflow** on `main`), then run the Shortcut.

### Backup: AltServer from the PC

Use this if SideStore can't sign in or install. Set up AltStore Classic's AltServer on
Windows once ([instructions](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows):
iTunes and iCloud from Apple's website, device trust, Developer Mode, and iTunes'
"Sync with this iPhone over Wi-Fi"). Then, for each build:

1. Download `Freeify-unsigned-<run number>` from the Actions run and extract it, or use
   `C:\Users\Qi\Freeify-builds\Freeify-latest.ipa` if the build was already saved there.
2. Unlock the iPhone, on the same Wi-Fi as the PC (or plugged in).
3. AltServer tray icon → **Sideload .ipa…** → the iPhone →
   `C:\Users\Qi\Freeify-builds\Freeify-latest.ipa`.

### Keeping the library safe

- **Never delete the app** to fix a problem: saved audio lives inside it.
- Switching signing tools (iloader, SideStore, AltServer) can make the library look
  empty while the songs are still on the phone. Freeify keeps its library at a fixed
  path (`Application Support/default.store`) and tries to recover one from an app group
  if its own is empty; Settings → Library files shows what it finds.
- Builds are deliberately not published as a public SideStore/AltStore source.

## If YouTube stops working

YouTube access is unofficial and can break when YouTube changes. Saved songs keep
playing offline. If Freeify reports a sign-in, bot check, or request limit, wait rather
than pressing Play repeatedly; signing into Safari or the YouTube app doesn't help
Freeify. [ROADMAP.md](ROADMAP.md) §2 lists what to try, in order. In October 2026 a
"Login is required" block was fixed by taking playback's visitor ID from a youtube.com
watch page, and background requests are now paced 30 seconds apart.

## Phone checks

After installing a new build:

1. Search YouTube Music and download a song. Its cover, title, and artist should appear
   in the library and on the lock screen.
2. Play it in airplane mode with the screen locked; lock-screen controls should work.
3. Let a song finish; the next one should play. Try shuffle and repeat.
4. Long-press a song, tap Play Next, and open the queue from the full-screen player.
5. Like a song and add it to a playlist; both should persist after reopening Freeify.
6. Remove a download and download it again; remove a song entirely.
7. Close and reopen Freeify; the last song should be paused where it stopped.
8. In Discover, Recently played should fill after a few plays; charts, new releases,
   and moods should open lists you can preview and download.
9. After playing, liking, or downloading a few songs, pull down on Discover; Made for
   you should show mixes. Not Interested should remove a song.
