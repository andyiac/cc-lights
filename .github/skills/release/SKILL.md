---
name: release
description: "Cut a new CC Lights release: pick the next semver, tag it, and let the GitHub Actions release workflow build and publish the packaged .dmg to GitHub Releases. Use when the user asks to release, ship a new version, cut/tag a release, publish a build, or upload the DMG to GitHub Releases."
license: MIT
metadata:
  author: andyiac
  version: "1.0"
---

# Release CC Lights

Publish a new version of CC Lights to
[GitHub Releases](https://github.com/andyiac/cc-lights/releases). The heavy
lifting is done by the tag-triggered workflow at
`.github/workflows/release.yml`, which runs `make dmg` on a macOS runner and
uploads `dist/CC-Lights-<version>.dmg` as a release asset.

**The normal path is: choose a version → push a `vX.Y.Z` tag → the workflow
builds and publishes the DMG.** You do not build or upload anything by hand
unless GitHub Actions is unavailable (see the manual fallback below).

## When to use

Use this skill when the user wants to:

- "release", "cut a release", "ship a new version", "bump the version"
- "publish the DMG", "put the build on GitHub Releases", "tag a release"

## Preconditions (check first)

1. **Clean, synced `main`.** The tag should point at reviewed code.
   ```bash
   git rev-parse --abbrev-ref HEAD          # expect: main
   git status --porcelain                   # expect: empty
   git fetch origin && git status -sb | head -1   # expect: up to date with origin/main
   ```
   If the tree is dirty or ahead/behind, resolve that before tagging.

2. **Repo settings (one-time).** The workflow needs Actions enabled and write
   permission. If a release run fails with a 403 when creating the release,
   fix: Settings → Actions → General → Workflow permissions → **Read and
   write**, and ensure Actions is allowed.

## Steps

### 1. Determine the next version

Follow semver (`MAJOR.MINOR.PATCH`). Look at the latest existing release/tag
and the changes since it:

```bash
# Prefer gh if available; otherwise use tags.
gh release list --limit 5 2>/dev/null || git tag -l 'v*' --sort=-v:refname | head -5
git log "$(git describe --tags --abbrev=0 2>/dev/null)"..HEAD --oneline 2>/dev/null || git log --oneline -15
```

- Bug fixes / docs only → bump PATCH (`0.1.0` → `0.1.1`).
- New backward-compatible features → bump MINOR (`0.1.1` → `0.2.0`).
- Breaking changes → bump MAJOR.

If the user gave a version, use it. Otherwise propose one and confirm.

> The workflow writes the tag's version into `Resources/Info.plist`
> (`CFBundleShortVersionString`) **before** building, so the app version and
> the DMG filename always match the tag. You do **not** need to edit
> `Info.plist` yourself.

### 2. Tag and push (triggers the release)

Use the helper script (validates semver, checks branch/tree, pushes with a
retry because this remote occasionally drops the first push):

```bash
.github/skills/release/scripts/release.sh 0.2.0
```

Or do it manually:

```bash
git tag -a v0.2.0 -m "CC Lights 0.2.0"
git push origin v0.2.0
```

Pushing the tag starts the **Release** workflow. You can also start it from the
GitHub UI: Actions → Release → Run workflow → enter the version
(`workflow_dispatch`).

### 3. Watch the build and verify the asset

```bash
# Watch the run (if gh is installed and authenticated)
gh run watch "$(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId')"

# Verify the release + DMG asset exist
gh release view v0.2.0
```

Success criteria: a `CC Lights 0.2.0` release exists at
`https://github.com/andyiac/cc-lights/releases/tag/v0.2.0` with a
`CC-Lights-0.2.0.dmg` asset attached. Report the release URL to the user.

## Re-running / fixing a release

- **Re-run a failed build:** `gh run rerun <run-id>` (the workflow uploads with
  `--clobber`, so re-running replaces the asset on an existing release).
- **Wrong tag:** delete it locally and remotely, then re-tag:
  ```bash
  git tag -d v0.2.0
  git push origin :refs/tags/v0.2.0
  gh release delete v0.2.0 --yes   # if a release was already created
  ```
  Never move an already-published tag that users may have downloaded; prefer a
  new patch version instead.

## Manual fallback (only if GitHub Actions is unavailable)

Build locally on macOS and upload the DMG yourself:

```bash
make dmg                                   # produces dist/CC-Lights-<version>.dmg
gh release create v0.2.0 dist/CC-Lights-*.dmg \
  --title "CC Lights 0.2.0" --generate-notes
# or, on an existing release:
gh release upload v0.2.0 dist/CC-Lights-*.dmg --clobber
```

Without `gh`, create the release and drag the DMG in through the web UI at
`https://github.com/andyiac/cc-lights/releases/new`.

## Notes

- The DMG is **ad-hoc signed**, not notarized, so first launch on another Mac
  needs right-click → Open. Notarization can be added later with Apple
  Developer secrets in the workflow.
- If the repo is **private**, release assets are only downloadable by users
  with repo access, and macOS runner minutes bill at a higher multiplier.
- Keep `README.md` install instructions and any version references in sync with
  the release when they change.
