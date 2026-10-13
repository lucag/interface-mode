#!/bin/sh
#
# Check that commit messages name an issue (#<n>). Merge commits are exempt.
#
#   check-commit-messages.sh --file <message-file>   one message (commit-msg hook)
#   check-commit-messages.sh <revision-range>        each commit in the range (CI)

set -eu

names_an_issue() {
  # Comment lines are dropped from the message, as git drops them.
  grep -v '^#' | grep -Eq '#[0-9]+'
}

reject() {
  echo "commit message must name its issue, e.g. 'Refs #4' or 'Closes #6': $1" >&2
  exit 1
}

if [ "${1:-}" = --file ]; then
  names_an_issue <"$2" || reject "$(head -n 1 "$2")"
  exit 0
fi

for commit in $(git rev-list --no-merges "$1"); do
  git log -1 --format=%B "$commit" | names_an_issue ||
    reject "$(git log -1 --format='%h %s' "$commit")"
done
