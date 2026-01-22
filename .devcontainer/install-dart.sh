#!/bin/bash

TEMP_DIR=$(mktemp -d)
echo "created $TEMP_DIR"
cd "$TEMP_DIR"

curl https://storage.googleapis.com/dart-archive/channels/stable/release/latest/linux_packages/dart_3.10.7-1_amd64.deb --output dart.deb
echo "downloaded dart"

apt-get install ./dart.deb
echo "installed dart"

cd /
rm -rf "$TEMP_DIR"
