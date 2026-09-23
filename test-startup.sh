#!/bin/sh -e
echo "Attempting startup..."
"${EMACS:=emacs}" -Q --batch -l "$(dirname "$0")/scripts/test-startup.el"
echo "Startup successful"
