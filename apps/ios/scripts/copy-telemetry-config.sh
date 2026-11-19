#!/bin/sh
set -eu

config_dir=${CUBEGIN_TELEMETRY_CONFIG_DIR:-"$SRCROOT/TelemetryConfig"}
resources="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
production_bundle=io.github.deweyou.cubegin
development_bundle=io.github.deweyou.cubegin.dev

mkdir -p "$resources"
rm -f "$resources/GoogleService-Info.plist" "$resources/sentry-dsn.txt"

case "$PLATFORM_NAME:$CONFIGURATION:$PRODUCT_BUNDLE_IDENTIFIER" in
    "iphoneos:Release:$production_bundle"|"iphoneos:Debug:$development_bundle") ;;
    *) exit 0 ;;
esac

firebase_config="$config_dir/$PRODUCT_BUNDLE_IDENTIFIER.plist"
sentry_dsn="$config_dir/$PRODUCT_BUNDLE_IDENTIFIER.sentry-dsn.txt"
if [ ! -e "$firebase_config" ] && [ ! -e "$sentry_dsn" ] && [ -z "${CUBEGIN_TELEMETRY_CONFIG_DIR:-}" ]; then
    exit 0
fi
if [ ! -s "$firebase_config" ] || [ ! -s "$sentry_dsn" ]; then
    echo "error: Both Firebase and Sentry configuration files are required for $PRODUCT_BUNDLE_IDENTIFIER."
    exit 1
fi
if [ "$(/usr/bin/plutil -extract BUNDLE_ID raw "$firebase_config")" != "$PRODUCT_BUNDLE_IDENTIFIER" ]; then
    echo "error: Firebase configuration does not match the app Bundle ID."
    exit 1
fi

production_firebase="$config_dir/$production_bundle.plist"
development_firebase="$config_dir/$development_bundle.plist"
if [ -f "$production_firebase" ] && [ -f "$development_firebase" ]; then
    production_project=$(/usr/bin/plutil -extract PROJECT_ID raw "$production_firebase")
    development_project=$(/usr/bin/plutil -extract PROJECT_ID raw "$development_firebase")
    if [ "$production_project" = "$development_project" ]; then
        echo "error: Debug and Release must use separate Firebase projects."
        exit 1
    fi
fi

production_sentry="$config_dir/$production_bundle.sentry-dsn.txt"
development_sentry="$config_dir/$development_bundle.sentry-dsn.txt"
if [ -f "$production_sentry" ] && [ -f "$development_sentry" ]; then
    # The numeric path identifies the project even if the project uses multiple client keys.
    production_project=$(awk -F / 'NF { gsub(/[[:space:]]/, "", $NF); print $NF; exit }' "$production_sentry")
    development_project=$(awk -F / 'NF { gsub(/[[:space:]]/, "", $NF); print $NF; exit }' "$development_sentry")
    if [ "$production_project" = "$development_project" ]; then
        echo "error: Debug and Release must use separate Sentry projects."
        exit 1
    fi
fi

cp "$firebase_config" "$resources/GoogleService-Info.plist"
cp "$sentry_dsn" "$resources/sentry-dsn.txt"
