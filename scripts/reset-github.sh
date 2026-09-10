#!/usr/bin/env bash
#
# reset-github.sh — delete every issue and milestone in the repository so the
# backlog can be recreated from scratch by bootstrap-github.sh.
#
# WARNING: issue deletion is PERMANENT. GitHub offers no undo. Only run this
# against a repository whose backlog is disposable — typically right after a
# bad bootstrap run, before any real discussion has happened on the issues.
#
# Usage:
#   ./scripts/reset-github.sh                    # asks for confirmation
#   REPO=owner/name ./scripts/reset-github.sh    # target a specific repo
#   FORCE=1 ./scripts/reset-github.sh            # skip the confirmation prompt

set -euo pipefail

REPO_NAME="keybridge"

command -v gh >/dev/null 2>&1 || {
  echo "error: gh is not installed.  Run: brew install gh" >&2; exit 1; }

gh auth status >/dev/null 2>&1 || {
  echo "error: gh is not authenticated.  Run: gh auth login" >&2; exit 1; }

if [[ -z "${REPO:-}" ]]; then
  OWNER="$(gh api user --jq .login)"
  REPO="${OWNER}/${REPO_NAME}"
fi

ISSUE_COUNT="$(gh issue list --repo "$REPO" --state all --limit 500 --json number --jq 'length')"
MS_COUNT="$(gh api "repos/${REPO}/milestones?state=all" --jq 'length')"

echo "Repository: ${REPO}"
echo "  issues to delete:     ${ISSUE_COUNT}"
echo "  milestones to delete: ${MS_COUNT}"
echo

if [[ "${FORCE:-0}" != "1" ]]; then
  read -r -p "This cannot be undone. Type 'delete' to proceed: " CONFIRM
  [[ "$CONFIRM" == "delete" ]] || { echo "Aborted."; exit 1; }
fi

echo "==> Deleting issues…"
for n in $(gh issue list --repo "$REPO" --state all --limit 500 --json number --jq '.[].number'); do
  gh issue delete "$n" --repo "$REPO" --yes >/dev/null
  echo "    · deleted #${n}"
done

echo "==> Deleting milestones…"
for m in $(gh api "repos/${REPO}/milestones?state=all" --jq '.[].number'); do
  gh api -X DELETE "repos/${REPO}/milestones/${m}" >/dev/null
  echo "    · deleted milestone ${m}"
done

echo
echo "==> Reset complete. Recreate the backlog with:"
echo "    ./scripts/bootstrap-github.sh"
