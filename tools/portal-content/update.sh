#!/usr/bin/env bash
# Fetches Microsoft's portal migration scripts (scripts.v3) at a given version into vendor/.
#
#   tools/portal-content/update.sh            # latest release
#   tools/portal-content/update.sh 2.36.0     # specific release (git tag)
#
# Afterwards: review git diff tools/portal-content, test 'make portal-capture' against dev, commit.
set -euo pipefail

REPO_URL="https://github.com/Azure/api-management-developer-portal.git"
FILES=(utils.js capture.js generate.js cleanup.js)   # only what the workflow needs
HERE="$(cd "$(dirname "$0")" && pwd)"
VENDOR="$HERE/vendor"

ref="${1:-}"
if [ -z "$ref" ]; then
  # Latest release = highest version tag (plain git, no GitHub API).
  ref="$(git ls-remote --tags --refs "$REPO_URL" | sed 's#.*refs/tags/##' \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
fi
echo "Fetching scripts.v3 from $REPO_URL @ $ref ..."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git -c advice.detachedHead=false clone -q --depth 1 --branch "$ref" --filter=blob:none --sparse "$REPO_URL" "$tmp/repo"
git -C "$tmp/repo" sparse-checkout set scripts.v3
commit="$(git -C "$tmp/repo" rev-parse HEAD)"

rm -rf "$VENDOR"
mkdir -p "$VENDOR/scripts.v3"
for f in "${FILES[@]}"; do
  cp "$tmp/repo/scripts.v3/$f" "$VENDOR/scripts.v3/$f"
done
cp "$tmp/repo/LICENSE" "$VENDOR/LICENSE"

cat > "$VENDOR/UPSTREAM" <<INFO
repository: $REPO_URL
ref: $ref
commit: $commit
path: scripts.v3
files: ${FILES[*]}
INFO

# Compare the packages the scripts require() with the upstream package.json.
git -C "$tmp/repo" sparse-checkout add /package.json >/dev/null 2>&1 || true
if [ -f "$tmp/repo/package.json" ]; then
  echo "Upstream versions of the required packages (compare with package.json here):"
  jq -r '(.dependencies // {}) + (.devDependencies // {}) | to_entries[]
         | select(.key == "@azure/storage-blob" or .key == "mime" or .key == "yargs")
         | "  \(.key) \(.value)"' "$tmp/repo/package.json"
fi
echo "vendor/ updated to $ref ($commit)."
