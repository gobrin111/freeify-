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

Playback establishes an anonymous visitor session before requesting audio, even
when starting from a cached Discover list before searching. Concurrent first
requests share that initialization, and requests use the visitor issued by
YouTube consistently. Stopping previews or switching songs cancels obsolete
work; late results cannot restart an old preview. This is a client-session fix,
not a guarantee that YouTube will allow playback.

If YouTube explicitly asks for sign-in or bot verification, Freeify reports that
requirement. Opening the song in YouTube lets you listen there; signing into
Safari or the YouTube app does not authenticate Freeify. A request limit requires
waiting rather than repeatedly pressing Play. Saved audio still works offline.

The Mac workflow runs session regression checks before building. To verify on the
phone: relaunch Freeify, play from a cached Discover list before searching, then
test a search preview and a download. Also stop and restart the same preview
quickly and switch songs while loading; old results must not take over playback.
If verification persists, capture the exact error details and whether downloading
that same song also fails. These device checks remain unverified for this patch.

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

### Agent-assisted builds

The repository skill [.agents/skills/freeify-build/SKILL.md](.agents/skills/freeify-build/SKILL.md)
guides Codex through finding the correct build, inspecting failures, and downloading
the resulting package. Open this `freeify-` directory as the Codex project to make
the repository skill discoverable, then request `$freeify-build`. From the parent
directory, ask Codex to read the skill at that path explicitly.

One-time prerequisites are working GitHub access and CLI authentication in the
environment running Codex, plus GitHub Actions enabled for this repository.
Authenticate through the browser with the command above; do not send credentials
in chat. A skill supplies instructions, not a background agent: GitHub runs builds
after pushes even when Codex is closed, while investigation and fixes require an
active Codex task.

These changes automate compilation only. An AltStore update source and TestFlight
delivery are not configured. Phone installation remains a separate setup step;
an unsigned artifact is not evidence of an installed or tested app.

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
