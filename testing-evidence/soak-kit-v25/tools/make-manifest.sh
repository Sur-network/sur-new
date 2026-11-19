#!/bin/bash
# Writes MANIFEST.sha256 (sha256 of every kit file, without runs/, .state/, verification/ and MANIFEST itself). Check on the server with:
#   sha256sum -c MANIFEST.sha256        (line endings: the kit must be copied with LF endings; .gitattributes enforces this for git)
cd "$(dirname "$0")/.." || exit 1
find . -type f ! -path './runs/*' ! -path './.state/*' ! -path './verification/*' ! -name MANIFEST.sha256 | sort | xargs sha256sum > MANIFEST.sha256
wc -l MANIFEST.sha256
