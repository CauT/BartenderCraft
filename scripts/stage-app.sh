#!/bin/bash
# Source after setting APP_DESTINATION. Build and validate APP before publish_app.
# Staging beside the destination keeps the final moves on the same filesystem.
mkdir -p "$(dirname "$APP_DESTINATION")"
APP_STAGING_ROOT=$(mktemp -d "$(dirname "$APP_DESTINATION")/.app-stage.XXXXXX")
APP="$APP_STAGING_ROOT/$(basename "$APP_DESTINATION")"

cleanup_app_stage() {
    local result=$?
    if [[ -d "$APP_STAGING_ROOT/previous.app" && ! -e "$APP_DESTINATION" ]]; then
        # Restore the prior app if publishing failed after moving it aside.
        mv "$APP_STAGING_ROOT/previous.app" "$APP_DESTINATION" || return 1
    fi
    rm -rf "$APP_STAGING_ROOT"
    return "$result"
}
trap cleanup_app_stage EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

publish_app() {
    if [[ -e "$APP_DESTINATION" ]]; then
        mv "$APP_DESTINATION" "$APP_STAGING_ROOT/previous.app"
    fi
    mv "$APP" "$APP_DESTINATION"
    printf 'Built %s\n' "$APP_DESTINATION"
}
