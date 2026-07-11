#!/usr/bin/env bash
# Cut a CC Lights release: validate, tag vX.Y.Z, and push (triggering the
# .github/workflows/release.yml build + DMG publish). Optionally watches the run.
#
# Usage:
#   .github/skills/release/scripts/release.sh <version> [--allow-dirty] [--no-watch]
#
# Examples:
#   .github/skills/release/scripts/release.sh 0.2.0
#   .github/skills/release/scripts/release.sh 1.0.0 --no-watch
set -euo pipefail

VERSION=""
ALLOW_DIRTY=0
WATCH=1

for arg in "$@"; do
  case "$arg" in
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --no-watch)    WATCH=0 ;;
    -h|--help)
      grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "Unknown option: $arg" >&2
      exit 2
      ;;
    *)
      if [ -n "$VERSION" ]; then
        echo "Unexpected extra argument: $arg" >&2
        exit 2
      fi
      VERSION="$arg"
      ;;
  esac
done

if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version> [--allow-dirty] [--no-watch]" >&2
  echo "  <version> is a semver like 0.2.0 (no leading 'v')" >&2
  exit 2
fi

# Accept an optional leading 'v', then normalize to the bare version.
VERSION="${VERSION#v}"
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$'; then
  echo "Error: '$VERSION' is not a valid semver (expected MAJOR.MINOR.PATCH)." >&2
  exit 2
fi
TAG="v$VERSION"

cd "$(git rev-parse --show-toplevel)"

# --- Preconditions ---------------------------------------------------------
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" != "main" ]; then
  echo "Warning: you are on '$BRANCH', not 'main'. Releases usually come from main." >&2
fi

if [ "$ALLOW_DIRTY" -eq 0 ] && [ -n "$(git status --porcelain)" ]; then
  echo "Error: working tree is not clean. Commit/stash first, or pass --allow-dirty." >&2
  git status --short >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "Error: tag $TAG already exists locally. Pick a new version or delete it first:" >&2
  echo "  git tag -d $TAG && git push origin :refs/tags/$TAG" >&2
  exit 1
fi

# Make sure we are not behind the remote (best effort; don't fail if offline).
if git fetch --quiet origin 2>/dev/null; then
  if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "Error: tag $TAG already exists on origin." >&2
    exit 1
  fi
  UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [ -n "$UPSTREAM" ]; then
    BEHIND="$(git rev-list --count "HEAD..$UPSTREAM" 2>/dev/null || echo 0)"
    if [ "$BEHIND" != "0" ]; then
      echo "Error: local $BRANCH is $BEHIND commit(s) behind $UPSTREAM. Pull first." >&2
      exit 1
    fi
  fi
fi

# --- Tag -------------------------------------------------------------------
echo "==> Creating annotated tag $TAG at $(git rev-parse --short HEAD)"
git tag -a "$TAG" -m "CC Lights $VERSION"

# --- Push (with a couple of retries; this remote sometimes drops the first) --
push_tag() {
  local attempt
  for attempt in 1 2 3; do
    if git push origin "$TAG"; then
      return 0
    fi
    echo "   push attempt $attempt failed; retrying in 3s..." >&2
    sleep 3
  done
  return 1
}

echo "==> Pushing $TAG to origin"
if ! push_tag; then
  echo "Error: failed to push $TAG after retries. The tag exists locally; re-run:" >&2
  echo "  git push origin $TAG" >&2
  exit 1
fi

echo "==> Pushed. The Release workflow should now be building the DMG."
echo "    Releases: https://github.com/andyiac/cc-lights/releases/tag/$TAG"

# --- Optionally watch the run ----------------------------------------------
if [ "$WATCH" -eq 1 ] && command -v gh >/dev/null 2>&1; then
  echo "==> Waiting for the Release workflow run to start..."
  RUN_ID=""
  for _ in $(seq 1 15); do
    RUN_ID="$(gh run list --workflow=release.yml --limit 1 \
      --json databaseId,headBranch --jq '.[0].databaseId' 2>/dev/null || true)"
    [ -n "$RUN_ID" ] && break
    sleep 2
  done
  if [ -n "$RUN_ID" ]; then
    gh run watch "$RUN_ID" --exit-status || {
      echo "Release run did not succeed. Inspect: gh run view $RUN_ID --log-failed" >&2
      exit 1
    }
    echo "==> Release published:"
    gh release view "$TAG" --json url,assets \
      --jq '"  " + .url + "\n  assets: " + ([.assets[].name] | join(", "))' 2>/dev/null || true
  else
    echo "   Could not find the run yet. Check the Actions tab." >&2
  fi
elif [ "$WATCH" -eq 1 ]; then
  echo "   (Install and auth the GitHub CLI 'gh' to auto-watch the build.)"
fi
