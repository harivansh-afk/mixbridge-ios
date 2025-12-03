#!/bin/sh

# ci_post_clone.sh
# Automatically increment build number for Xcode Cloud builds

set -e

echo "Setting build number to $CI_BUILD_NUMBER"

# Navigate to the project directory
cd "$CI_PRIMARY_REPOSITORY_PATH"

# Update build number in project.pbxproj using agvtool
# This uses CI_BUILD_NUMBER which auto-increments with each Xcode Cloud build
agvtool new-version -all "$CI_BUILD_NUMBER"

echo "Build number set to $CI_BUILD_NUMBER"
