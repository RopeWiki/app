#!/bin/bash

# This script is to be ran after a successful deployment of the ropewiki stack.
# It tags docker images and github commits with versions numbers which can be used in future as known "good versions".

RW_SITE_VERSION=${1:?This script expects a version tag as the first argument. Run "git tag" to see current version tags.}

images=(
    "backup_manager"
    "database"
    "mailserver"
    "reverse_proxy"
    "webserver"
)

for image in "${images[@]}"; do
    docker tag ropewiki/$image:latest ropewiki/$image:${RW_SITE_VERSION}
    docker push ropewiki/$image:${RW_SITE_VERSION}
    docker push ropewiki/$image:latest
done

echo
echo "########################"
echo
echo "Remember to create and push the git tag $RW_SITE_VERSION. This needs to be done from a checkout with write access to github."
echo "  git checkout $(git rev-parse HEAD)"
echo "  git tag ${RW_SITE_VERSION}"
echo "  git push origin ${RW_SITE_VERSION}"
echo
echo "########################"
echo