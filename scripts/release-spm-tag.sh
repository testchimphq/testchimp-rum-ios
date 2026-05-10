#!/usr/bin/env bash
# SwiftPM releases are git tags on this repo — there is no separate registry (JitPack is for JVM).
# Usage: ./scripts/release-spm-tag.sh 0.1.0
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:?Usage: $0 <semver_tag_example_0.1.0>}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
  echo "Warning: tag '$VERSION' is not SemVer-shaped; continuing anyway."
fi

echo "Consumers will add:"
echo "  .package(url: \"https://github.com/testchimphq/testchimp-rum-ios.git\", from: \"$VERSION\")"
echo ""
read -r -p "Create annotated git tag '$VERSION' and push to origin? [y/N] " ok
if [[ "${ok:-}" != "y" && "${ok:-}" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Error: working tree or index is not clean. Commit or stash first." >&2
  exit 1
fi

git tag -a "$VERSION" -m "Release $VERSION"
git push origin "$VERSION"

echo "Done. Xcode / SwiftPM resolves the tag from the public Git URL (no JitPack)."
