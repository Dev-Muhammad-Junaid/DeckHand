#!/usr/bin/env bash
#
# Sets the version of BOTH apps in project.yml (they release together).
#
#   ./bump-version.sh 1.1          # marketing 1.1, build number +1
#   ./bump-version.sh 1.1 42       # marketing 1.1, build number 42
#
# Sparkle decides "newer" by the build number (CFBundleVersion), so it must
# go up on every release, including betas. The marketing version is what
# people see.

set -euo pipefail
source "$(dirname "$0")/config.sh"

new_version="${1:-}"
[[ -n "$new_version" ]] || die "usage: $0 <marketing-version> [build-number]"
[[ "$new_version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || die "marketing version must look like 1.2 or 1.2.3"

old_build="$(project_build_number)"
new_build="${2:-$((old_build + 1))}"
[[ "$new_build" =~ ^[0-9]+$ ]] || die "build number must be an integer"
(( new_build > old_build )) || die "build number must go up (currently $old_build)"

yml="$APP_PROJECT_DIR/project.yml"
# Every target's MARKETING_VERSION / CURRENT_PROJECT_VERSION line.
sed -i '' -E \
    -e "s/^( +MARKETING_VERSION: ).*/\1\"$new_version\"/" \
    -e "s/^( +CURRENT_PROJECT_VERSION: ).*/\1$new_build/" \
    "$yml"

log "project.yml: $VERSION ($old_build) → $new_version ($new_build)"
grep -nE 'MARKETING_VERSION|CURRENT_PROJECT_VERSION' "$yml"
echo
echo "Commit it:  git commit -am \"Bump version to $new_version ($new_build)\""
