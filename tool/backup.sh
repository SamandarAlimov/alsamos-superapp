#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="${ALSAMOS_BACKUP_SERVER:-ubuntu@92.4.76.166}"
SSH_KEY="${ALSAMOS_BACKUP_KEY:-$HOME/.ssh/alsamos}"
BARE_REPO="${ALSAMOS_BACKUP_BARE:-~/backups/alsamos.git}"
FILES_DIR="${ALSAMOS_BACKUP_FILES:-~/backups/alsamos-files}"
SSH_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=accept-new)

cd "$REPO_ROOT"

ssh "${SSH_OPTS[@]}" "$SERVER" "mkdir -p $BARE_REPO && git init --bare $BARE_REPO >/dev/null"

git config core.sshCommand "ssh -i $SSH_KEY"
if git remote get-url backup >/dev/null 2>&1; then
  git remote set-url backup "$SERVER:$BARE_REPO"
else
  git remote add backup "$SERVER:$BARE_REPO"
fi

git push --all backup
git push --tags backup

if command -v rsync >/dev/null 2>&1; then
  rsync -az --delete -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new" \
    --exclude .git/ \
    --exclude build/ \
    --exclude .dart_tool/ \
    --exclude node_modules/ \
    "$REPO_ROOT/" "$SERVER:$FILES_DIR/"
else
  ssh "${SSH_OPTS[@]}" "$SERVER" "rm -rf $FILES_DIR && mkdir -p $FILES_DIR"
  tar \
    --exclude='./.git' \
    --exclude='./build' \
    --exclude='./.dart_tool' \
    --exclude='./node_modules' \
    -czf - . | ssh "${SSH_OPTS[@]}" "$SERVER" "tar -xzf - -C $FILES_DIR"
fi

echo "Backup complete: git=$SERVER:$BARE_REPO files=$SERVER:$FILES_DIR"
