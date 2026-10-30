# Freeify

A personal iPhone music app written in Swift and SwiftUI: search YouTube Music,
save songs on the phone, and play them offline, including with the screen locked.
Progress and next steps are tracked in [ROADMAP.md](ROADMAP.md).

## Features

Freeify has three tabs, with the player bar above them.

- **Discover:** recently played songs, "Made for you" mixes built from what you
  play, like, and save, plus YouTube Music charts, new releases, and moods &
  genres. Play buttons in those lists play in the player, streaming songs that
  aren't saved, and the full-screen player's "Playing from" opens the list again.
  **Download All** saves a list's songs into a playlist with its name. Listening
  history and recommendation feedback stay on the phone.
- **Search:** YouTube Music's Songs tab, with cover art and more results as you
  scroll. Play streams a preview without saving; download saves the song with its
  cover art using [YouTubeKit](https://github.com/b5i/YouTubeKit), pinned to a
  specific commit. Long-press a result to start a radio of similar songs. This is
  unofficial and can break when YouTube changes; `ROADMAP.md` notes what to check
  first.
- **Library:** search by title or artist, sort, and see how much space saved
  songs use. Swipe left to remove a song or only its download (YouTube songs
  download again with a tap); select several songs from the More (…) menu. Swipe
  right or long-press to like a song or add it to a playlist. Liked Songs and
  Playlists are at the top. **Add from Files** copies an audio file into Freeify;
  Freeify never scans the phone's files.
- **Playback:** the list a song is played from becomes the queue. Next/previous,
  shuffle, and repeat work in the app and on the lock screen. Long-press a song
  for Play Next, Add to Queue, or Start Radio. Tap the player bar for the
  full-screen player and queue. Shuffle, repeat, and the last song are remembered.

There are no music service credentials, backend, or cloud library sync.

### YouTube verification errors

Playback gets its anonymous visitor ID once per app session from a youtube.com
watch page's config, the source yt-dlp uses, even when starting from a cached
Discover list before searching. Search and Discover keep YouTube Music's own
visitor. In October 2026 YouTube answered "Login is required" to playback that
used YouTube Music's visitor; the watch-page visitor fixed it on the phone.
Concurrent first requests share that initialization. Stopping previews or
switching songs cancels obsolete work; late results cannot restart an old preview.
Freeify keeps no cookies, since it never signs in.

Requests are kept at a listening pace. The background loudness lookup for older
downloads waits 30 seconds before each song; looking up the whole library at once
likely set off that bot check. Avoid adding features that send YouTube bursts of
requests.

If YouTube explicitly asks for sign-in or bot verification, Freeify reports that
requirement. Opening the song in YouTube lets you listen there; signing into
Safari or the YouTube app does not authenticate Freeify. A request limit requires
waiting rather than repeatedly pressing Play. Saved audio still works offline.
If it happens again, `ROADMAP.md` lists what to try, in order.

The Mac workflow runs session regression checks before building.

Requires iOS 17 or newer. The build uses the Xcode version installed by default
on GitHub's `macos-15` runner and prints that version in its log. The app uses
Swift 5 language mode with the installed Swift compiler.

## Build from Windows with GitHub Actions

GitHub Actions runs the build on a temporary Mac and saves a downloadable
artifact. Your phone does not connect to that Mac while using Freeify.

1. Commit and push these files to the repository's default branch, `main`.
2. App, Xcode project, and build-workflow changes automatically start a build.
   Open [this repository's Actions tab](https://github.com/gobrin111/freeify-/actions).
3. To build manually instead, choose **Build Freeify for iPhone**, then
   **Run workflow** on `main`. Avoid starting a second build for the same push.
4. Open the completed run. A successful run has a green check.
5. Under **Artifacts**, download `Freeify-unsigned-<run number>`.
6. Extract the downloaded ZIP to get `Freeify-unsigned.ipa`.

If using the GitHub CLI, authenticate in your terminal with
`gh auth login --hostname github.com --web`. Never put account passwords, tokens,
or signing certificates into the repository. The build needs no Apple account
or repository secrets because signing happens when you sideload it.

The workflow runs for relevant pushes to `main` or on manual request, has a
20-minute timeout, and retains
artifacts for seven days. GitHub provides a plan-dependent allowance for private
repositories; macOS usage beyond that allowance may be charged. See
[GitHub runner documentation](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

If a build fails, open the failing step and download the build diagnostics
artifact. A local configuration check is not proof that the Swift app compiles;
each updated version still needs a successful Mac build before device testing.

### Builds with Claude Code

The skill [.claude/skills/freeify-build](.claude/skills/freeify-build/SKILL.md)
(`/freeify-build`) finds the build for a commit, waits for it, shows the failing
step if it breaks, and downloads the IPA to Windows:

- `C:\Users\Qi\Freeify-builds\<run number>\Freeify-unsigned.ipa`
- `C:\Users\Qi\Freeify-builds\Freeify-latest.ipa`, always the newest, for iloader

Its script, `fetch_ipa.sh [commit]`, also runs on its own from WSL. It checks that
the download is a valid package whose build number matches the run, and keeps the
five newest builds. It needs `gh` signed in (command above). Installing stays manual
with iloader; a downloaded IPA is not evidence of an installed or tested app.

### YouTube tester (for Claude Code)

`tools/youtube_tester/server.py` is a local MCP server that sends Freeify's exact
YouTube requests from the PC: `search_songs`, `visitor_id`, `check_playback`
(YouTube's status and reason, the audio formats Freeify would use, and a first-byte
check of the audio URL), `ytdlp_compare`, and `network_info`. Use it first when
playback breaks; `ROADMAP.md` lists what to try after. Its request values mirror
`Freeify/YouTubeSearch.swift` (the `SYNC` block): change both together. It is a
developer tool on the PC; the app never depends on it.

Setup, once (already registered for this user):

```
cd tools/youtube_tester
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
claude mcp add --scope user freeify-youtube-tester -- "$PWD/.venv/bin/python" "$PWD/server.py"
```

Update its yt-dlp now and then (`.venv/bin/pip install -U "yt-dlp[default]"`) so
`ytdlp_compare` reflects YouTube's current state.

## Install on your iPhone

The `.ipa` is **unsigned**. It cannot be installed merely by opening it in Files.
Use a signing/sideloading tool such as AltStore Classic with AltServer on Windows.
Follow the [official Windows setup instructions](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows),
including device trust and Developer Mode. Once AltStore is installed, transfer
the `.ipa` to your iPhone and select it with **+** in AltStore's **My Apps** tab.

AltServer is a local installation/refresh helper on your PC. Freeify's playback
does not depend on it. With a free Apple account, sideloaded apps expire after
seven days unless refreshed. Keep this in mind before extended offline travel.
See [AltStore's refresh documentation](https://faq.altstore.io/altstore-classic/your-altstore).
Compatibility with your exact iOS release must be checked during installation.

## Phone checks

After installing a new build:

1. Search YouTube Music for a song title and download a result. Its cover art,
   title, and artist should appear in the library and on the lock screen.
2. Play it in airplane mode with the screen locked; lock-screen controls should work.
3. Let a song finish; the next one should play. Try shuffle and repeat.
4. Long-press a song, tap Play Next, and open the queue from the full-screen player.
5. Like a song and add it to a playlist; both should persist after reopening Freeify.
6. Remove a download and download it again from the library; remove a song entirely.
7. Close and reopen Freeify; the last song should be paused where it stopped.
8. In Discover, recently played songs should appear after playing a few. Charts,
   new releases, and moods should open lists you can preview and download.
9. After playing, liking, or downloading a few YouTube Music songs, pull down on
   Discover; "Made for you" should show mixes. Long-press a song there and choose
   Not Interested; it should disappear.
