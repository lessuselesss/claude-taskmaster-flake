#!/usr/bin/env bash
#
# Bulk-transfer repositories from a GitHub user to an organization.
#
# Run this LOCALLY, on a machine where `gh` is authenticated as the source
# user with a token that has repo transfer rights. Do NOT run it in a
# sandbox/CI without a deliberate reason — transfers are irreversible.
#
# Defaults to a DRY RUN. Review the printed plan, then re-run with DRY_RUN=0.
#
# Usage:
#   ./transfer-repos.sh                 # dry run with the defaults below
#   DRY_RUN=0 ./transfer-repos.sh       # actually transfer
#   SRC_USER=me DEST_ORG=my-org DRY_RUN=0 ./transfer-repos.sh
#
# Env vars:
#   SRC_USER       source user       (default: lessuselesss)
#   DEST_ORG       destination org   (default: lessuseless-OG)
#   DRY_RUN        1 = plan only (default), 0 = execute
#   INCLUDE_FORKS  1 = include forks (default: 0, source repos only)
#   INCLUDE_ARCHIVED 1 = include archived repos (default: 0, skipped+listed)
#   SLEEP_SECS     pause between transfers (default: 2, avoids rate limits)
#   LIMIT          max repos to list  (default: 1000)

set -euo pipefail

SRC_USER="${SRC_USER:-lessuselesss}"
DEST_ORG="${DEST_ORG:-lessuseless-OG}"
DRY_RUN="${DRY_RUN:-1}"
INCLUDE_FORKS="${INCLUDE_FORKS:-0}"
INCLUDE_ARCHIVED="${INCLUDE_ARCHIVED:-0}"
SLEEP_SECS="${SLEEP_SECS:-2}"
LIMIT="${LIMIT:-1000}"

ts="$(date +%Y%m%d-%H%M%S)"
ok_log="transferred-${ts}.log"
fail_log="failed-${ts}.log"

die() { echo "error: $*" >&2; exit 1; }

# --- prerequisites --------------------------------------------------------
command -v gh >/dev/null 2>&1 || die "gh CLI not found. Install: https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "gh not authenticated. Run: gh auth login"

# Transfers need repo administration rights. Classic token: 'repo' scope.
# Fine-grained: Administration:write on both user and org. If SSO is enforced
# on the org, authorize the token for the org first.
if ! gh auth status 2>&1 | grep -qiE "'repo'|repo,|admin:org|Administration"; then
  echo "warning: could not confirm token has repo/admin scope."
  echo "         If transfers 403, run: gh auth refresh -s repo,admin:org"
  echo
fi

# --- list repos -----------------------------------------------------------
source_flag=(--source)
[ "$INCLUDE_FORKS" = "1" ] && source_flag=()

echo "Listing repos for '$SRC_USER' (forks: $([ "$INCLUDE_FORKS" = 1 ] && echo yes || echo no))..."
mapfile -t rows < <(
  gh repo list "$SRC_USER" --limit "$LIMIT" "${source_flag[@]}" \
    --json name,visibility,isArchived \
    -q '.[] | [.name, .visibility, (.isArchived|tostring)] | @tsv'
)

[ "${#rows[@]}" -gt 0 ] || die "no repositories returned for '$SRC_USER'"

# --- plan -----------------------------------------------------------------
to_transfer=()
skipped_archived=()
for row in "${rows[@]}"; do
  IFS=$'\t' read -r name visibility archived <<<"$row"
  if [ "$archived" = "true" ] && [ "$INCLUDE_ARCHIVED" != "1" ]; then
    skipped_archived+=("$name")
    continue
  fi
  to_transfer+=("$name|$visibility|$archived")
done

echo
echo "Source:      $SRC_USER"
echo "Destination: $DEST_ORG"
echo "Will transfer: ${#to_transfer[@]} repo(s)"
[ "${#skipped_archived[@]}" -gt 0 ] && \
  echo "Skipping ${#skipped_archived[@]} archived repo(s) (set INCLUDE_ARCHIVED=1 to include): ${skipped_archived[*]}"
echo

for entry in "${to_transfer[@]}"; do
  IFS='|' read -r name visibility archived <<<"$entry"
  echo "  - $name ($visibility$([ "$archived" = true ] && echo ", archived"))"
done
echo

# --- execute --------------------------------------------------------------
if [ "$DRY_RUN" = "1" ]; then
  echo "DRY RUN. Nothing was transferred. Re-run with DRY_RUN=0 to execute."
  exit 0
fi

read -r -p "Transfer ${#to_transfer[@]} repo(s) from '$SRC_USER' to '$DEST_ORG'? Type YES to proceed: " reply
[ "$reply" = "YES" ] || die "aborted"

: > "$ok_log"; : > "$fail_log"
for entry in "${to_transfer[@]}"; do
  IFS='|' read -r name visibility archived <<<"$entry"
  echo "transferring $name ..."
  if gh api -X POST "repos/$SRC_USER/$name/transfer" \
       -f new_owner="$DEST_ORG" --silent 2>>"$fail_log"; then
    echo "$name" >> "$ok_log"
  else
    echo "FAILED: $name"
    echo "$name" >> "$fail_log"
  fi
  sleep "$SLEEP_SECS"
done

echo
echo "Done. Transferred: $(wc -l < "$ok_log") | Failed: see $fail_log"
echo "Success log: $ok_log"
echo "Failure log: $fail_log"
echo
echo "Reminder — these do NOT survive a transfer and must be re-applied on the org:"
echo "  * repo-level Actions secrets & variables"
echo "  * team access / permissions"
echo "  * branch protection rulesets referencing user-level actors"
echo "  * GitHub Pages custom domains (re-verify)"
echo "  * published packages (may need relinking)"
echo
echo "To re-point a local clone:  git remote set-url origin git@github.com:$DEST_ORG/<repo>.git"
