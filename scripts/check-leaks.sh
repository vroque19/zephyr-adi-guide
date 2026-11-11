#!/usr/bin/env bash
# Usage: check-leaks.sh [paths...]  (default: git ls-files)
# Exit 0 clean, 1 leak found, 2 error (unreadable path, grep failure, git failure).
# Patterns use bracket tricks (e.g. hom[e], User[s]) so this file does not match itself.
# -a: treat binary files as text so NUL-containing files are still scanned.
set -u
if [ "$#" -gt 0 ]; then
  files=("$@")
else
  # Always scan the whole repo, regardless of the cwd the script is run from.
  if ! top=$(git rev-parse --show-toplevel) || ! cd "$top"; then
    echo "check-leaks: not inside a git repository" >&2; exit 2
  fi
  if ! listing=$(git ls-files); then echo "check-leaks: git ls-files failed" >&2; exit 2; fi
  files=()
  [ -n "$listing" ] && while IFS= read -r f; do files+=("$f"); done <<<"$listing"
fi
[ "${#files[@]}" -eq 0 ] && exit 0

status=0
for f in "${files[@]}"; do
  if [ ! -f "$f" ] || [ ! -r "$f" ]; then
    echo "check-leaks: cannot read file: $f" >&2; status=2
  fi
done
[ "$status" -ne 0 ] && exit 2

run() { # run <grep flags...> -- ; pattern and files passed via globals
  grep -naH "$@" -- "${files[@]}"
  rc=$?
  case $rc in
    0) [ "$status" -lt 1 ] && status=1 ;;
    1) ;;
    *) echo "check-leaks: grep failed (rc=$rc)" >&2; status=2 ;;
  esac
}
run -iE -e '[\\/]hom[e][\\/][^\\/[:space:]]+'
run -iE -e '[\\/]User[s][\\/][^\\/[:space:]]+'
run -E  -e '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
[ -n "${USER:-}" ] && run -iF -e "$USER"
exit $status
