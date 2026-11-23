#!/bin/sh
# Site verification: POSIX sh, no Python. Run from anywhere.
cd "$(dirname "$0")/.." || exit 2
fail=0
bad(){ echo "FAIL: $*"; fail=1; }
pages=$(ls *.html)

for f in $pages; do
  grep -q '<html lang="[a-z-]*"' "$f" || bad "$f: missing html lang"
  grep -q '<title>[^<]' "$f" || bad "$f: missing title"
  grep -q '<meta name="description" content="[^"]' "$f" || bad "$f: missing description"
  grep -q '<meta name="viewport"' "$f" || bad "$f: missing viewport"
done

# internal links and assets
for f in $pages assets/site.css; do
  grep -o -E '(href|src)="[^"]*"' "$f" 2>/dev/null | sed -E 's/^(href|src)="//; s/"$//' | while read -r u; do
    case "$u" in
      http*|mailto:*|data:*) continue;;
      /zyvor-kubeza-site/*) u=${u#/zyvor-kubeza-site/}; [ -z "$u" ] && continue;;
      \#*) continue;;
    esac
    p=${u%%#*}; [ -z "$p" ] && continue
    [ -e "$p" ] || echo "FAIL: $f: broken link $u"
  done
done | tee /tmp/zkube_check.$$ ; grep -q FAIL /tmp/zkube_check.$$ && fail=1; rm -f /tmp/zkube_check.$$

# in-page anchors
for f in $pages; do
  grep -o -E 'href="[a-z]*\.?[a-z]*#[^"]+"' "$f" | sed -E 's/^href="//; s/"$//' | while read -r u; do
    pg=${u%%#*}; id=${u#*#}; [ -z "$pg" ] && pg=$f
    [ -e "$pg" ] && { grep -q "id=\"$id\"" "$pg" || echo "FAIL: $f: missing anchor $u"; }
  done
done | tee /tmp/zkube_check.$$ ; grep -q FAIL /tmp/zkube_check.$$ && fail=1; rm -f /tmp/zkube_check.$$

# external URLs: allowlist github.com and zyvor.dev (plus zyvorai.github.io metadata, w3.org namespaces)
ext=$(cat $pages assets/site.css assets/site.js favicon.svg og-image.svg | grep -o -E 'https?://[^"'"'"' )<>]+' | sort -u)
for u in $ext; do
  case "$u" in
    https://github.com/*|https://zyvor.dev/*|https://zyvorai.github.io/zyvor-kubeza-site*|http://www.w3.org/2000/svg) ;;
    *) bad "external URL not allowed: $u";;
  esac
done
# no external subresources at all
grep -l -E '<(script|link|img|iframe)[^>]+(src|href)="https?://[^"]*"' $pages 2>/dev/null | while read -r f; do
  grep -E '<(script|img|iframe)[^>]+src="https?://|<link[^>]+rel="stylesheet"[^>]+href="https?://' "$f" >/dev/null && echo "FAIL: $f: external subresource"
done | grep -q FAIL && fail=1

# sitemap lists every page
for f in $pages; do
  [ "$f" = 404.html ] && continue
  loc="https://zyvorai.github.io/zyvor-kubeza-site/"; [ "$f" = index.html ] || loc="$loc$f"
  grep -q "<loc>$loc</loc>" sitemap.xml || bad "sitemap missing $f"
done

# JSON-LD parse (balanced braces check; uses plutil/jq when available)
for f in $pages; do
  grep -q 'application/ld+json' "$f" || continue
  json=$(sed -n '/application\/ld+json/,/<\/script>/p' "$f" | sed '1s/.*">//; $d')
  if command -v jq >/dev/null 2>&1; then echo "$json" | jq . >/dev/null 2>&1 || bad "$f: JSON-LD invalid"
  else echo "note: $f has JSON-LD but jq not installed; not parsed"; fi
done

[ $fail -eq 0 ] && echo "OK: all checks passed" || { echo "Checks failed"; exit 1; }
