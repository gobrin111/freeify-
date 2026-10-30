---
name: freeify-build
description: Build Freeify on GitHub's Mac and save the unsigned IPA on the user's Windows PC. Use after pushing app changes, when the user asks for a build, an IPA, or why a build failed, or with /freeify-build.
---

# Freeify build and download

Freeify can't be compiled here (Windows/WSL, no Mac). `.github/workflows/ios-build.yml`
builds an **unsigned** IPA on `macos-15` for pushes to `main` that touch `Freeify/**`,
`Freeify.xcodeproj/**`, `Tests/**`, or the workflow; docs-only pushes start no build.
The user installs the IPA with iloader on Windows. Installing is theirs, not yours.

## Steps

1. **Commit and push only when the user said so.** Leave the untracked `.agents/` folder
   out. End commit messages with the Co-Authored-By line from the system reminder. Never
   force-push.
2. **Run** `.claude/skills/freeify-build/fetch_ipa.sh [commit]` (default `HEAD`) from the
   repo, with a 10-minute Bash timeout. It finds that commit's run (never "the latest
   run"), waits for it, downloads `Freeify-unsigned-<run number>`, checks the zip and that
   the IPA's build number equals the run number, and saves:
   - `C:\Users\Qi\Freeify-builds\<run number>\Freeify-unsigned.ipa`
   - `C:\Users\Qi\Freeify-builds\Freeify-latest.ipa` (only moves forward to newer builds)

   It keeps the five newest numbered builds. Override the folder with `FREEIFY_BUILDS_DIR`.
3. **Read the exit code:**
   - `0` saved. Give the user the run link, the build number, and the Windows path.
   - `1` build failed (the script prints the failed step's last 60 log lines) or the IPA
     didn't check out. For compile errors, fix the code, then ask before pushing again.
     At most two fix-and-rebuild rounds per request; then report what's still failing.
     For a fuller log: `gh run view <run id> --repo gobrin111/freeify- --log-failed`.
   - `2` no run for that commit: it isn't pushed, or it changed no app files. If a build
     is wanted anyway, `gh workflow run ios-build.yml --repo gobrin111/freeify- --ref main`,
     then rerun the script with that commit.
   - `3` `gh` isn't signed in. The user runs `! gh auth login --hostname github.com --web`.
     Don't retry logins, and don't treat a network failure as a sign-in problem.

## What a successful build proves

Only that the app compiles and packages. It is not an install, and not a phone test:
never mark ROADMAP items `[x]` or say a feature works until the user confirms it on the
phone. A newer push cancels an older run of the same branch (`cancel-in-progress`), so a
`cancelled` run is not a failure of that code. Artifacts expire after seven days.

Never put Apple credentials, signing certificates, tokens, or cookies in the repo.
