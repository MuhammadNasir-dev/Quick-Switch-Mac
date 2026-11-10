#!/usr/bin/env bash
# Reports how many times each QuickSwitch release has been downloaded.
#
# Counts *downloads*, not people. A download is not an install: the same person
# re-downloading, or grabbing both architectures, counts twice. Treat it as a
# floor on reach and a good signal of which Macs your users actually have.
#
# Only .dmg assets are counted — that is the only thing published.
#
# Needs no token for a public repository. Set GITHUB_TOKEN to raise the
# unauthenticated rate limit of 60 requests an hour.
set -euo pipefail

REPO="${1:-MuhammadNasir-dev/Quick-Switch-Mac}"
API="https://api.github.com/repos/$REPO/releases?per_page=100"

# macOS ships bash 3.2, where `"${arr[@]}"` on an empty array trips `set -u`.
if [ -n "${GITHUB_TOKEN:-}" ]; then
  response="$(curl -fsSL -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" "$API")" || {
    echo "Could not reach the GitHub API for $REPO" >&2
    exit 1
  }
else
  response="$(curl -fsSL -H "Accept: application/vnd.github+json" "$API")" || {
    echo "Could not reach the GitHub API for $REPO" >&2
    exit 1
  }
fi

printf '%s' "$response" | python3 -c '
import json, sys

releases = json.load(sys.stdin)
if not releases:
    print("No releases published yet - tag one with: git tag v1.0.0 && git push origin v1.0.0")
    raise SystemExit

total = 0
by_arch = {}

for release in releases:
    assets = [a for a in release.get("assets", []) if a["name"].endswith(".dmg")]
    if not assets:
        continue
    subtotal = sum(a["download_count"] for a in assets)
    total += subtotal
    tag = release["tag_name"]
    published = release.get("published_at", "")[:10]
    print("{:<14} {:<12} {:>8} downloads".format(tag, published, subtotal))
    for asset in sorted(assets, key=lambda a: a["name"]):
        print("    {:<46} {:>8}".format(asset["name"], asset["download_count"]))
        for arch in ("apple-silicon", "intel", "universal", "arm64", "x86_64"):
            if arch in asset["name"]:
                by_arch[arch] = by_arch.get(arch, 0) + asset["download_count"]
                break

print()
print("{:<27} {:>8} downloads".format("TOTAL", total))
for arch, count in sorted(by_arch.items(), key=lambda kv: -kv[1]):
    share = (count / total * 100) if total else 0
    print("  {:<25} {:>8}  ({:.0f}%)".format(arch, count, share))
'
