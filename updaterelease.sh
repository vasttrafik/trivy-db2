#!/usr/bin/env bash

set -e

releasesurl='https://api.github.com/repos/aquasecurity/trivy/releases/latest'
architecture=$(uname -m | sed 's/x86_64/64bit/g' | sed 's/aarch64/ARM64/g' | sed 's/arm64/ARM64/g')
echo "architecture: '$architecture'"
jqpattern='.assets[] | select(.name|test("^trivy_[0-9\\.]+_Linux-'$architecture'\\.tar\\.gz$")) | .browser_download_url'
echo "jqpattern '$jqpattern'"
asseturl=$(curl -s "$releasesurl" | jq "$jqpattern" -r)
echo "asseturl: '$asseturl'"
filename=$(basename "$asseturl")
echo "Downloading: '$asseturl' -> '$filename'"
curl -Ls "$asseturl" -o "$filename"
tar xf "$filename"
rm "$filename"
rm LICENSE
rm README.md
rm -rf contrib

./trivy image --download-db-only

echo 'Downloaded db.'

rm trivy
cp -r ~/.cache/trivy .
tar cf - trivy | gzip -9 > trivydb2.tar.gz

baseurl="https://api.github.com/repos/$GITHUB_REPOSITORY"
baseurluploads="https://uploads.github.com/repos/$GITHUB_REPOSITORY"
accept="Accept: application/vnd.github+json"
auth="Authorization: Bearer $1"
apiversion="X-GitHub-Api-Version: 2022-11-28"
contenttype="Content-Type: application/zip"

echo 'Retrieving release...'
latest=$(curl -s -H "$accept" -H "$auth" -H "$apiversion" "$baseurl/releases/latest")

if [ ! -z "$latest" ]; then
  RELEASE_ID=$(jq -r '.id' <<< "$latest")
  echo "Got release id: '"$RELEASE_ID"'"

  if [ ! -z "$RELEASE_ID" ] && [ "$RELEASE_ID" != "null" ] ; then
    echo 'Deleting release...'
    curl -s -X DELETE -H "$accept" -H "$auth" -H "$apiversion" "$baseurl/releases/$RELEASE_ID" > /dev/null
  fi
fi

json='{"tag_name":"v1.0.'"$GITHUB_RUN_NUMBER"'","name":"v1.0.'"$GITHUB_RUN_NUMBER"'"}'

echo 'Creating new release...'
newrelease=$(curl -s -X POST -H "$accept" -H "$auth" -H "$apiversion" "$baseurl/releases" -d "$json")

if [ -z "$newrelease" ]; then
  echo "Couldn't get release id."
  exit 1
fi

RELEASE_ID=$(jq -r '.id' <<< "$newrelease")
echo "Got release id: '"$RELEASE_ID"'"

if [ -z "$RELEASE_ID" ] || [ "$RELEASE_ID" = "null" ]; then
  echo "Couldn't get release id."
  exit 1
fi

echo 'Uploading asset...'
curl -s -X POST -H "$accept" -H "$auth" -H "$apiversion" "$baseurluploads/releases/$RELEASE_ID/assets?name=trivydb2.tar.gz" --data-binary "@trivydb2.tar.gz" -H "$contenttype" > /dev/null

echo 'Done!'
