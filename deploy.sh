#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  Website Builder — GitHub Pages Deploy Script  v2.0
#  Learned from: Victor Energy Drink project deployment
# ═══════════════════════════════════════════════════════════════
#
#  Usage:
#    bash deploy.sh <TOKEN> <USERNAME> <REPO_NAME> <HTML_FILE> [CUSTOM_DOMAIN]
#
#  Arguments:
#    TOKEN          GitHub Personal Access Token (needs 'repo' scope)
#                   Create one at: https://github.com/settings/tokens/new
#    USERNAME       Your GitHub username
#    REPO_NAME      Repository name (becomes part of the URL)
#    HTML_FILE      Path to your main HTML file (will be deployed as index.html)
#    CUSTOM_DOMAIN  Optional: your custom domain e.g. "www.mysite.com"
#                   (requires DNS CNAME → <username>.github.io)
#
#  Examples:
#    bash deploy.sh ghp_xxx myuser victor-energy /mnt/user-data/outputs/victor-energy.html
#    bash deploy.sh ghp_xxx myuser victor-energy /mnt/user-data/outputs/victor-energy.html www.victordrinked.com
#
#  Live URL after deploy:
#    https://<USERNAME>.github.io/<REPO_NAME>
#    (or your custom domain if provided)
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
BLU='\033[0;34m'; CYN='\033[0;36m'; WHT='\033[1;37m'; NC='\033[0m'

ok()   { echo -e "  ${GRN}✅${NC}  $*"; }
warn() { echo -e "  ${YLW}⚠️ ${NC}  $*"; }
err()  { echo -e "  ${RED}❌${NC}  $*"; }
info() { echo -e "  ${CYN}▸${NC}  $*"; }
head() { echo -e "\n${WHT}$*${NC}"; }

# ── Args ──────────────────────────────────────────────────────
GITHUB_TOKEN="${1:-}"
GITHUB_USER="${2:-}"
REPO_NAME="${3:-}"
HTML_FILE="${4:-}"
CUSTOM_DOMAIN="${5:-}"

# ── Validate ──────────────────────────────────────────────────
if [[ -z "$GITHUB_TOKEN" || -z "$GITHUB_USER" || -z "$REPO_NAME" || -z "$HTML_FILE" ]]; then
  echo -e "${WHT}Usage:${NC} bash deploy.sh <TOKEN> <USERNAME> <REPO_NAME> <HTML_FILE> [CUSTOM_DOMAIN]"
  echo ""
  echo "  TOKEN        — GitHub PAT with 'repo' scope"
  echo "  USERNAME     — Your GitHub username"
  echo "  REPO_NAME    — Repository name (e.g. victor-energy)"
  echo "  HTML_FILE    — Path to your HTML file"
  echo "  CUSTOM_DOMAIN — Optional: e.g. www.yoursite.com"
  echo ""
  echo "  Get a token → https://github.com/settings/tokens/new"
  exit 1
fi

if [[ ! -f "$HTML_FILE" ]]; then
  err "File not found: $HTML_FILE"
  exit 1
fi

FILE_SIZE=$(wc -c < "$HTML_FILE")
if [[ "$FILE_SIZE" -lt 100 ]]; then
  err "HTML file appears empty or too small ($FILE_SIZE bytes). Aborting."
  exit 1
fi

# ── Banner ────────────────────────────────────────────────────
echo ""
echo -e "${YLW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YLW}  ⚡  Website Builder — GitHub Pages Deploy v2.0  ${NC}"
echo -e "${YLW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${BLU}User:${NC}   $GITHUB_USER"
echo -e "  ${BLU}Repo:${NC}   $REPO_NAME"
echo -e "  ${BLU}File:${NC}   $HTML_FILE ($(numfmt --to=iec $FILE_SIZE 2>/dev/null || echo "${FILE_SIZE}B"))"
[[ -n "$CUSTOM_DOMAIN" ]] && echo -e "  ${BLU}Domain:${NC} $CUSTOM_DOMAIN"
echo ""

# ── Pre-flight: social link check ────────────────────────────
head "▸ Pre-flight checks"
DEAD_LINKS=$(grep -c 'href="#"' "$HTML_FILE" || true)
if [[ "$DEAD_LINKS" -gt 0 ]]; then
  warn "$DEAD_LINKS dead href=\"#\" links found in your HTML."
  warn "Consider wiring social/contact links before deploying (see SKILL.md Phase 15)."
else
  ok "No dead href=\"#\" links found"
fi

# Check for placeholder text
if grep -qi "lorem ipsum\|your company\|placeholder" "$HTML_FILE" 2>/dev/null; then
  warn "Possible placeholder text detected — review before deploying."
else
  ok "No placeholder text detected"
fi

# ── Build deploy directory ────────────────────────────────────
head "▸ Preparing deploy package"
DEPLOY_DIR="/tmp/deploy-$$-$REPO_NAME"
mkdir -p "$DEPLOY_DIR"

# Copy HTML as index.html
cp "$HTML_FILE" "$DEPLOY_DIR/index.html"
ok "Copied HTML → index.html"

# Copy any sibling assets (images, fonts, css, js) if they exist
HTML_DIR="$(dirname "$HTML_FILE")"
ASSET_COUNT=0
for ext in png jpg jpeg gif webp svg ico css js woff woff2 ttf; do
  for asset in "$HTML_DIR"/*."$ext" 2>/dev/null; do
    [[ -f "$asset" ]] && cp "$asset" "$DEPLOY_DIR/" && ASSET_COUNT=$((ASSET_COUNT+1))
  done
done
[[ "$ASSET_COUNT" -gt 0 ]] && ok "Copied $ASSET_COUNT sibling assets" || info "No sibling assets to copy"

# Add CNAME file for custom domain
if [[ -n "$CUSTOM_DOMAIN" ]]; then
  echo "$CUSTOM_DOMAIN" > "$DEPLOY_DIR/CNAME"
  ok "Created CNAME → $CUSTOM_DOMAIN"
fi

# Add minimal 404.html that redirects to index (SPA fallback)
cat > "$DEPLOY_DIR/404.html" << 'EOF'
<!DOCTYPE html>
<html><head>
<meta charset="UTF-8">
<script>
  // GitHub Pages SPA fallback — redirect 404s to index
  const path = window.location.pathname;
  window.location.replace('/' + window.location.pathname.split('/').slice(1).join('/').replace(/^[^?]*/, '') + window.location.search);
</script>
</head><body></body></html>
EOF
ok "Created 404.html (SPA fallback)"

# ── Create GitHub repo ────────────────────────────────────────
head "▸ Creating GitHub repository"
CREATE_RESP=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/user/repos" \
  -d "{\"name\":\"$REPO_NAME\",\"private\":false,\"auto_init\":false,\"description\":\"Deployed via Website Builder skill — Claude AI\"}" \
  2>/dev/null)

HTTP_CODE=$(echo "$CREATE_RESP" | tail -1)
BODY=$(echo "$CREATE_RESP" | head -n -1)

case "$HTTP_CODE" in
  201) ok "Repository created → github.com/$GITHUB_USER/$REPO_NAME" ;;
  422) warn "Repository already exists — will force-push to it" ;;
  401) err "Authentication failed. Check your GitHub token has 'repo' scope."; exit 1 ;;
  403) err "Forbidden. Token may lack 'repo' permissions."; exit 1 ;;
  *)
    warn "GitHub API returned HTTP $HTTP_CODE"
    echo ""
    echo -e "  ${YLW}👉  Manual step needed:${NC}"
    echo "  1. Go to https://github.com/new"
    echo "  2. Name: $REPO_NAME | Visibility: Public | No README"
    echo "  3. Press Enter here once created."
    echo ""
    read -rp "  Press Enter to continue..." _
    ;;
esac

# ── Git push ──────────────────────────────────────────────────
head "▸ Pushing to GitHub"
cd "$DEPLOY_DIR"

git init -q
git config user.email "deploy@website-builder.claude.ai"
git config user.name "Claude Website Builder"
git checkout -b main -q 2>/dev/null || git checkout -b main 2>/dev/null || true
git add -A
git commit -q -m "🚀 Deploy: $(date '+%Y-%m-%d %H:%M') — via Claude Website Builder"

REMOTE_URL="https://$GITHUB_TOKEN@github.com/$GITHUB_USER/$REPO_NAME.git"
git remote add origin "$REMOTE_URL" 2>/dev/null || git remote set-url origin "$REMOTE_URL"

if git push -u origin main --force -q 2>&1; then
  ok "Pushed to github.com/$GITHUB_USER/$REPO_NAME"
else
  err "Push failed. Verify:"
  err "  • Token has 'repo' scope: https://github.com/settings/tokens"
  err "  • Repository exists: https://github.com/$GITHUB_USER/$REPO_NAME"
  cd / && rm -rf "$DEPLOY_DIR"
  exit 1
fi

# ── Enable GitHub Pages ───────────────────────────────────────
head "▸ Enabling GitHub Pages"

# Small wait for GitHub to register the push
sleep 2

PAGES_RESP=$(curl -s -w "\n%{http_code}" -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$GITHUB_USER/$REPO_NAME/pages" \
  -d '{"source":{"branch":"main","path":"/"}}' \
  2>/dev/null)

PAGES_CODE=$(echo "$PAGES_RESP" | tail -1)

case "$PAGES_CODE" in
  201) ok "GitHub Pages enabled automatically" ;;
  409) ok "GitHub Pages already enabled — site will update shortly" ;;
  *)
    warn "Couldn't auto-enable Pages (API returned $PAGES_CODE)"
    echo ""
    echo -e "  ${YLW}👉  Manual step — takes 30 seconds:${NC}"
    echo "  1. Go to: https://github.com/$GITHUB_USER/$REPO_NAME/settings/pages"
    echo "  2. Source: Deploy from a branch"
    echo "  3. Branch: main  |  Folder: / (root)  →  Save"
    ;;
esac

# ── Custom domain setup ───────────────────────────────────────
if [[ -n "$CUSTOM_DOMAIN" ]]; then
  head "▸ Configuring custom domain"
  DOMAIN_RESP=$(curl -s -w "\n%{http_code}" -X PUT \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/$GITHUB_USER/$REPO_NAME/pages" \
    -d "{\"cname\":\"$CUSTOM_DOMAIN\"}" \
    2>/dev/null)
  DOMAIN_CODE=$(echo "$DOMAIN_RESP" | tail -1)
  if [[ "$DOMAIN_CODE" == "200" || "$DOMAIN_CODE" == "204" ]]; then
    ok "Custom domain set → $CUSTOM_DOMAIN"
  else
    warn "Custom domain API returned $DOMAIN_CODE — CNAME file was still pushed."
    warn "Add a CNAME DNS record: $CUSTOM_DOMAIN → $GITHUB_USER.github.io"
  fi
fi

# ── Cleanup ───────────────────────────────────────────────────
cd /
rm -rf "$DEPLOY_DIR"

# ── Success summary ───────────────────────────────────────────
echo ""
echo -e "${YLW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GRN}  🌐  Deployment Complete!${NC}"
echo -e "${YLW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
if [[ -n "$CUSTOM_DOMAIN" ]]; then
  echo -e "  ${WHT}Live URL (custom domain):${NC}"
  echo -e "  ${CYN}https://$CUSTOM_DOMAIN${NC}   ← live in ~5 min (DNS propagation)"
  echo ""
  echo -e "  ${WHT}GitHub Pages URL (always works):${NC}"
fi
echo -e "  ${WHT}Live URL:${NC}"
echo -e "  ${CYN}https://$GITHUB_USER.github.io/$REPO_NAME${NC}   ← live in ~60 seconds"
echo ""
echo -e "  ${WHT}Repository:${NC}"
echo -e "  ${BLU}https://github.com/$GITHUB_USER/$REPO_NAME${NC}"
echo ""
if [[ -n "$CUSTOM_DOMAIN" ]]; then
  echo -e "  ${YLW}DNS Setup Required:${NC}"
  echo "  Add a CNAME record:"
  echo "  $CUSTOM_DOMAIN  →  $GITHUB_USER.github.io"
  echo ""
fi
echo -e "${YLW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
