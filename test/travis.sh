#!/bin/sh

if [ "$GOON_ENABLED" = 1 ]; then
    mix test --trace --include localbin
else
    mix test --trace --exclude goon
fi
