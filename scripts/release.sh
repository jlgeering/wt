#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/release.sh <X.Y.Z>

Example:
  scripts/release.sh 0.1.1
USAGE
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
fi

VERSION="$1"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "version must match X.Y.Z"
fi

TAG="v$VERSION"
REPO="jlgeering/wt"

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "must run inside git repository"
cd "$ROOT_DIR"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "main" ]]; then
  fail "must release from main (current: $BRANCH)"
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  fail "working tree must be clean"
fi
if [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  fail "working tree has untracked files"
fi

if ! git remote get-url github >/dev/null 2>&1; then
  fail "missing github remote"
fi

mise x -- gh auth status >/dev/null

git fetch github main --tags
if ! git merge-base --is-ancestor github/main HEAD; then
  fail "local main is behind github/main; pull or rebase first"
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  fail "local tag already exists: $TAG"
fi
if git ls-remote --exit-code --tags github "refs/tags/$TAG" >/dev/null 2>&1; then
  fail "remote tag already exists: $TAG"
fi

ZON_VERSION="$(sed -n 's/^[[:space:]]*\.version = "\([0-9][0-9.]*\)",/\1/p' build.zig.zon | head -n1)"
if [[ "$ZON_VERSION" != "$VERSION" ]]; then
  fail "build.zig.zon version ($ZON_VERSION) does not match requested version ($VERSION)"
fi

DEFAULT_BUILD_VERSION="$(sed -n 's/.*orelse "\([0-9][0-9.]*\)".*/\1/p' build.zig | head -n1)"
if [[ "$DEFAULT_BUILD_VERSION" != "$VERSION" ]]; then
  fail "build.zig fallback version ($DEFAULT_BUILD_VERSION) does not match requested version ($VERSION)"
fi

NOTES_FILE="$(mktemp -t wt-release-notes.XXXXXX.md)"
ASSET_ROOT="$(mktemp -d -t wt-release-assets.XXXXXX)"
BUILD_ROOT="$ASSET_ROOT/build"
DIST_DIR="$ASSET_ROOT/dist"
cleanup() {
  rm -f "$NOTES_FILE"
  rm -rf "$ASSET_ROOT"
}
trap cleanup EXIT

awk -v ver="$VERSION" '
  BEGIN { capture = 0 }
  /^## \[/ {
    if (capture) exit
    if ($0 ~ "^## \\[" ver "\\]") capture = 1
  }
  capture { print }
' CHANGELOG.md > "$NOTES_FILE"

if ! grep -q "^## \[$VERSION\]" "$NOTES_FILE"; then
  fail "CHANGELOG.md is missing section for $VERSION"
fi

if [[ ! -s "$NOTES_FILE" ]]; then
  fail "release notes extracted from CHANGELOG.md are empty"
fi

echo "==> Running preflight checks"
mise run check

mkdir -p "$BUILD_ROOT" "$DIST_DIR"

echo "==> Building release binaries"
zig build -Dtarget=aarch64-macos -Doptimize=ReleaseSafe -Dapp_version="$VERSION" -p "$BUILD_ROOT/aarch64-macos"
zig build -Dtarget=x86_64-macos -Doptimize=ReleaseSafe -Dapp_version="$VERSION" -p "$BUILD_ROOT/x86_64-macos"
zig build -Dtarget=x86_64-linux -Doptimize=ReleaseSafe -Dapp_version="$VERSION" -p "$BUILD_ROOT/x86_64-linux"
zig build -Dtarget=aarch64-linux -Doptimize=ReleaseSafe -Dapp_version="$VERSION" -p "$BUILD_ROOT/aarch64-linux"
zig build -Dtarget=x86_64-windows -Doptimize=ReleaseSafe -Dapp_version="$VERSION" -p "$BUILD_ROOT/x86_64-windows"

HOST_BIN=""
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)
    HOST_BIN="$BUILD_ROOT/aarch64-macos/bin/wt"
    ;;
  Darwin-x86_64)
    HOST_BIN="$BUILD_ROOT/x86_64-macos/bin/wt"
    ;;
  Linux-x86_64)
    HOST_BIN="$BUILD_ROOT/x86_64-linux/bin/wt"
    ;;
  Linux-aarch64)
    HOST_BIN="$BUILD_ROOT/aarch64-linux/bin/wt"
    ;;
esac

if [[ -n "$HOST_BIN" ]]; then
  VERSION_OUTPUT="$($HOST_BIN --version)"
  if [[ ! "$VERSION_OUTPUT" =~ ^wt[[:space:]]$VERSION[[:space:]]\(.+\)$ ]]; then
    fail "host artifact version check failed: $VERSION_OUTPUT"
  fi
fi

echo "==> Packaging release archives"
tar -C "$BUILD_ROOT/aarch64-macos/bin" -czf "$DIST_DIR/wt-$TAG-darwin-arm64.tar.gz" wt
tar -C "$BUILD_ROOT/x86_64-macos/bin" -czf "$DIST_DIR/wt-$TAG-darwin-amd64.tar.gz" wt
tar -C "$BUILD_ROOT/aarch64-linux/bin" -czf "$DIST_DIR/wt-$TAG-linux-arm64.tar.gz" wt
tar -C "$BUILD_ROOT/x86_64-linux/bin" -czf "$DIST_DIR/wt-$TAG-linux-amd64.tar.gz" wt
(
  cd "$BUILD_ROOT/x86_64-windows/bin"
  zip -q "$DIST_DIR/wt-$TAG-windows-amd64.zip" wt.exe
)

(
  cd "$DIST_DIR"
  shasum -a 256 \
    "wt-$TAG-darwin-arm64.tar.gz" \
    "wt-$TAG-darwin-amd64.tar.gz" \
    "wt-$TAG-linux-arm64.tar.gz" \
    "wt-$TAG-linux-amd64.tar.gz" \
    "wt-$TAG-windows-amd64.zip" > SHA256SUMS
  shasum -a 256 -c SHA256SUMS >/dev/null
)

echo "==> Pushing main and tag"
git push github main
git tag -a "$TAG" -m "wt $TAG"
git push github "$TAG"

echo "==> Creating draft GitHub release"
mise x -- gh release create "$TAG" \
  "$DIST_DIR/wt-$TAG-darwin-arm64.tar.gz" \
  "$DIST_DIR/wt-$TAG-darwin-amd64.tar.gz" \
  "$DIST_DIR/wt-$TAG-linux-arm64.tar.gz" \
  "$DIST_DIR/wt-$TAG-linux-amd64.tar.gz" \
  "$DIST_DIR/wt-$TAG-windows-amd64.zip" \
  "$DIST_DIR/SHA256SUMS" \
  --repo "$REPO" \
  --verify-tag \
  --title "wt $TAG" \
  --notes-file "$NOTES_FILE" \
  --draft

echo "==> Verifying draft release contents"
DRAFT_STATE="$(mise x -- gh release view "$TAG" --repo "$REPO" --json isDraft --jq '.isDraft')"
if [[ "$DRAFT_STATE" != "true" ]]; then
  fail "release is not draft before publish gate"
fi

ASSET_COUNT="$(mise x -- gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets | length')"
if [[ "$ASSET_COUNT" -ne 6 ]]; then
  fail "expected 6 release assets, found $ASSET_COUNT"
fi

BODY_LEN="$(mise x -- gh release view "$TAG" --repo "$REPO" --json body --jq '.body | length')"
if [[ "$BODY_LEN" -le 0 ]]; then
  fail "release notes body is empty"
fi

echo "==> Publishing release"
mise x -- gh release edit "$TAG" --repo "$REPO" --draft=false --latest

LATEST_TAG="$(mise x -- gh api "repos/$REPO/releases/latest" --jq '.tag_name')"
if [[ "$LATEST_TAG" != "$TAG" ]]; then
  fail "latest release is $LATEST_TAG, expected $TAG"
fi

RELEASE_URL="$(mise x -- gh release view "$TAG" --repo "$REPO" --json url --jq '.url')"
echo "Release published: $RELEASE_URL"
