#!/usr/bin/env bash
# ------------------------------------------------------------
# gradle-metadata.sh NAME: regenerate pkgs/aur/NAME/gradle-verification-metadata.xml
# for a pin that builds with Gradle (limine-mkinitcpio-hook,
# limine-snapper-sync). Gradle refuses any artifact whose sha256 is not in
# that file, so after a version bump that changes the Gradle build, the
# package fails to build until this is rerun:
#
#   scripts/dev/bump-aur.sh NAME --reviewer WHO      # moves the version
#   scripts/dev/gradle-metadata.sh NAME              # this
#   git diff pkgs/aur/NAME/gradle-verification-metadata.xml   # review: new
#                                                    # artifacts and versions
#   scripts/dev/bump-aur.sh NAME --reviewer WHO --sums-only   # repin the file
#
# Runs in archlinux:base-devel via podman or docker (IMAGE=,
# CONTAINER_ARGS=; JAVA_TOOL_OPTIONS as for build-repo.sh behind a proxy).
# It checks out the git tag the PKGBUILD names (the tag's signature is
# checked by makepkg at build time, not here), downloads the GraalVM JDK the
# PKGBUILD pins and checks its sha256, and runs the same Gradle task as
# build() with --write-verification-metadata sha256. The checksums are
# trust on first use from Maven Central: review the diff.
# ------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
IMAGE="${IMAGE:-docker.io/library/archlinux:base-devel}"
NAME="${1:?usage: gradle-metadata.sh NAME}"
DIR="$ROOT/pkgs/aur/$NAME"
PB="$DIR/PKGBUILD"
[[ -f "$DIR/gradle-verification-metadata.xml" ]] || { echo "$NAME has no gradle-verification-metadata.xml" >&2; exit 2; }

# The values, read by sourcing our own PKGBUILD (reviewed code).
eval "$(bash -c '
    source "$1" >/dev/null
    src="${source[0]}"; url="${src#*git+}"; url="${url%%#*}"; tag="${src##*#tag=}"; tag="${tag%%\?*}"
    printf "GIT_URL=%q\nGIT_TAG=%q\nJDK_URL=%q\nJDK_SUM=%q\n" "$url" "$tag" "${source_x86_64[0]}" "${sha256sums_x86_64[0]}"
' _ "$PB")"
[[ -n "$GIT_URL" && -n "$GIT_TAG" && -n "$JDK_URL" && -n "$JDK_SUM" ]] || { echo "Could not read the sources from $PB" >&2; exit 2; }
echo "==> $NAME: $GIT_URL tag $GIT_TAG, JDK $(basename "$JDK_URL")"

RUNTIME="$(command -v podman || command -v docker || true)"
[[ -n "$RUNTIME" ]] || { echo "Need podman or docker." >&2; exit 2; }
read -ra extra <<< "${CONTAINER_ARGS:-}"
env_args=(-e GIT_URL="$GIT_URL" -e GIT_TAG="$GIT_TAG" -e JDK_URL="$JDK_URL" -e JDK_SUM="$JDK_SUM")
if [[ -n "${JAVA_TOOL_OPTIONS:-}" ]]; then env_args+=(-e JAVA_TOOL_OPTIONS); fi
# shellcheck disable=SC2016 # expanded in the container
"$RUNTIME" run --rm -v "$DIR:/pkg" "${env_args[@]}" "${extra[@]}" "$IMAGE" bash -c '
    set -euo pipefail
    pacman -Syu --noconfirm --needed git gradle >/dev/null
    cd /tmp
    curl -sSfL -o jdk.tgz "$JDK_URL"
    echo "$JDK_SUM  jdk.tgz" | sha256sum -c - >/dev/null
    mkdir jdk && tar -xzf jdk.tgz -C jdk --strip-components=1
    export GRAALVM_HOME=/tmp/jdk JAVA_HOME=/tmp/jdk
    git clone -q --branch "$GIT_TAG" "$GIT_URL" src 2>/dev/null
    cd src
    gradle --no-daemon -q --write-verification-metadata sha256 clean nativeCompile -Dorg.gradle.java.home="$JAVA_HOME" >/tmp/gradle.log 2>&1 \
        || { tail -20 /tmp/gradle.log; exit 1; }
    cat gradle/verification-metadata.xml > /pkg/gradle-verification-metadata.xml'
echo "==> Wrote pkgs/aur/$NAME/gradle-verification-metadata.xml. Review the diff, then: scripts/dev/bump-aur.sh $NAME --reviewer <you> --sums-only"
