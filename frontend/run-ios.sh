#!/bin/bash
# Run expo ios build with clean compiler environment

# Save paths we need
NODE_BIN=$(dirname $(which node))
POD_BIN=$(dirname $(which pod))

# Run with minimal environment
exec env -i \
    HOME="$HOME" \
    USER="$USER" \
    SHELL="/bin/bash" \
    TERM="$TERM" \
    LANG="en_US.UTF-8" \
    PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:$NODE_BIN:$POD_BIN" \
    DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" \
    bash -c "cd '$PWD' && npx expo run:ios $*"
