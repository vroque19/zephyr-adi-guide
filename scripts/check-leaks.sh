#!/usr/bin/env bash
# Usage: check-leaks.sh [paths...]  (default: git ls-files)
# Exit 1 and print offending lines if personal paths, emails or the username appear.
set -u
if [ "$#" -gt 0 ]; then files=("$@"); else mapfile -t files < <(git ls-files); fi
[ "${#files[@]}" -eq 0 ] && exit 0
patterns=('/home/[a-z]+/' '/User[s]/' '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
[ -n "${USER:-}" ] && patterns+=("$USER")
status=0
for p in "${patterns[@]}"; do
  if grep -nEH -I -e "$p" -- "${files[@]}"; then status=1; fi
done
exit $status
