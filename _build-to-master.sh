#!/bin/sh

set -e

cd "$(dirname "$0")"

TEMP_MESSAGE_PATH=$(mktemp -t JekyllBuild)
trap 'rm -f ${TEMP_MESSAGE_PATH}' 0

exec 3>"${TEMP_MESSAGE_PATH}" # Open log file with fd 3
echo "Jekyll build" >&3
echo >&3

jekyll -v >&3 2>&3
uname -a >&3 2>&3
echo >&3
jekyll build >&3 2>&3

exec 3>&- # close log file

git add -f _site
SITE_TREE=$(git write-tree --prefix=_site/)
git reset _site >/dev/null

MASTER_SHA=$(git rev-parse master)
SOURCE_SHA=$(git rev-parse HEAD)

if [ "$SITE_TREE" = "$(git rev-parse master^{tree})" ]; then
    echo "No changes." >&2
    exit 0
fi

COMMIT=$(git commit-tree $SITE_TREE -p $MASTER_SHA -p $SOURCE_SHA -F "${TEMP_MESSAGE_PATH}")

git update-ref refs/heads/master $COMMIT -m "Jekyll build from ${SOURCE_SHA}"
