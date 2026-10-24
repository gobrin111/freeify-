# Freeify

A personal iPhone music app written in Swift and SwiftUI. The first milestone
establishes a Windows-to-iPhone build path and local audio playback.

## Current scope

- Import audio using the iPhone Files picker. Freeify copies it into its own
  storage, validates that it can be opened, and saves library metadata with SwiftData.
- Search titles in Freeify's saved library. Audio lives in the app's private
  Application Support/Audio directory; Freeify does not scan the phone's files.
  **Add from Files** opens Apple's picker only to select a file to copy into Freeify.
- Play, pause, and seek imported tracks without a network connection.
- Background audio and lock-screen controls, with interruption handling and
  pause when headphones disconnect.
- Build an unsigned iPhone `.ipa` with GitHub's temporary macOS runner.

YouTube search and downloading are **not implemented yet**. They require a
separate on-device feasibility check. This first build has no third-party
packages, music service credentials, backend, or cloud library sync.

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

## First-device checks

The user has confirmed that the existing build installs and plays imported audio.
The updated library search still needs a Mac build and device verification.
After installing:

1. Import an MP3 or M4A from Files. The title should appear in the library.
2. Close and reopen Freeify. The imported track should still be listed and playable.
3. Enable airplane mode, turn off Wi-Fi, and start the track. It should play offline.
4. Lock the screen for at least a minute. Audio should continue, and the lock-screen
   play/pause and seek controls should work. Locking the screen is supported;
   force-quitting Freeify stops playback.
5. Disconnect headphones during playback. Audio should pause.
6. Test an interruption such as a phone call. Resume only when iOS permits it.
7. Try an invalid audio file. The app should show an error without adding a broken
   library entry. Import two files with the same name; both should remain playable.
8. Search for an imported title in **Search Freeify library**. Partial titles and
   different capitalization should match; an unknown title should show **No matching
   songs**. Clearing the search (or entering only spaces) should restore the library.
9. Confirm an audio file that has not been imported never appears in library search.
   Add it with **Add from Files**, then confirm it is searchable and playable after
   reopening Freeify. Existing imported tracks should still work without reimporting.

The milestone passes when the GitHub build creates the `.ipa`, it installs, and
these checks succeed on the phone. YouTube integration, playlists, deletion,
and visual polish are outside this initial build milestone.
