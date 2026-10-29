#!/bin/sh
# ADR-171: reproducible setup of the store apps on a build machine.
#
#   PALEE_APP_ENV=production|staging|development  (default production)
#   PALEE_APP_URL=https://…                        (overrides the environment's URL)
#   PALEE_APS_ENVIRONMENT=production|development   (iOS push entitlement)
#   PALEE_BUILD_NUMBER=<n>                         (store build number; default config/release.json)
#
# The ios/ and android/ projects are in git (generated with `npx cap add`
# from the pinned Capacitor versions). This installs the exact JS versions,
# writes the environment into the native projects and syncs the plugins.
# Building needs Android Studio (SDK 36, JDK 21) and Xcode 26+ on macOS (App
# Store uploads need the iOS 26 SDK since 28 April 2026);
# signing material and Firebase files are owner actions (ADR-171,
# docs/release/signing-guide.md).
set -eu

cd "$(dirname "$0")/.."

npm ci --no-audit --no-fund

# Re-create a platform only if its folder was removed.
[ -d android ] || npx cap add android
[ -d ios ] || npx cap add ios

node scripts/configure.mjs
npx cap sync

if [ ! -f android/app/google-services.json ]; then
  echo "note: android/app/google-services.json is missing; Android push stays off until it is added."
fi

echo "Done. Open with: npx cap open android | npx cap open ios"
