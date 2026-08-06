#!/usr/bin/env bash
# =============================================================================
# publish_site.sh -- push the rendered site to the gh-pages branch.
#
#     bash publish_site.sh
#
# Run render_site.R first. Safe to re-run; each run replaces the published site.
#
# HOW IT WORKS
# ------------
# It uses a git WORKTREE: a second checkout of the same repository, on the
# gh-pages branch, in a temporary folder. The site is copied there, committed,
# and pushed. Your working directory and your main branch are never touched --
# no branch switching, no stashing, nothing to go wrong mid-edit.
#
# The gh-pages branch holds ONLY the rendered HTML. Source stays on main. That
# separation is why the published site can contain figures derived from data that
# is git-ignored on main.
# =============================================================================

set -euo pipefail

BRANCH="gh-pages"
SITE="_site"
TMP=".gh-pages-worktree"

command -v git >/dev/null || { echo "ERROR: git not installed."; exit 1; }
[ -d .git ] || { echo "ERROR: not a git repository. Run: bash setup_github.sh"; exit 1; }

if [ ! -f "$SITE/index.html" ]; then
  echo "ERROR: $SITE/index.html not found."
  echo "  Run this first:  Rscript -e 'source(\"render_site.R\")'"
  exit 1
fi

git remote get-url origin >/dev/null 2>&1 || {
  echo "ERROR: no 'origin' remote. Run: bash setup_github.sh"; exit 1; }

echo "=============================================================="
echo "  Publishing $SITE/ to the $BRANCH branch"
echo "=============================================================="

# --- create the branch on first run, with no history from main ---------------
if ! git show-ref --quiet "refs/heads/$BRANCH" && \
   ! git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  echo "  '$BRANCH' does not exist yet -- creating it as an orphan branch."
  git worktree add --detach "$TMP" >/dev/null
  ( cd "$TMP" && git checkout --orphan "$BRANCH" && git rm -rf . >/dev/null 2>&1 || true )
else
  git fetch origin "$BRANCH" 2>/dev/null || true
  git worktree add "$TMP" "$BRANCH" 2>/dev/null || \
    git worktree add -b "$BRANCH" "$TMP" "origin/$BRANCH"
fi

# --- replace contents, preserving .git ---------------------------------------
find "$TMP" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
cp -R "$SITE"/. "$TMP"/
touch "$TMP/.nojekyll"

cd "$TMP"
git add -A
if git diff --cached --quiet; then
  echo "  No changes since the last publish. Nothing to do."
else
  git commit -q -m "Rendered site: $(date -u '+%Y-%m-%d %H:%M UTC')"
  git push -q origin "HEAD:$BRANCH"
  echo "  pushed."
fi
cd ..
git worktree remove "$TMP" --force

URL=$(git remote get-url origin | sed -E 's#(git@|https://)github.com[:/]##; s#\.git$##')
USER=${URL%%/*}; REPO=${URL##*/}

cat <<MSG

--------------------------------------------------------------
  Published.

  https://${USER}.github.io/${REPO}/

  FIRST TIME ONLY -- enable Pages:
    Repository → Settings → Pages
    Source: "Deploy from a branch"
    Branch: gh-pages    Folder: / (root)
    Save

  Allow a minute or two for the first build.
--------------------------------------------------------------
MSG
