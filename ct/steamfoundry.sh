#!/usr/bin/env bash

export COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/Rabvc4/steamfoundry.sh/main}"
source <(curl -fsSL "$COMMUNITY_SCRIPTS_URL/misc/build.func")

# Copyright (c) 2026 Ryan Best
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://developer.valvesoftware.com/wiki/SteamCMD

APP="SteamFoundry"
var_tags="${var_tags:-gaming;server}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -x /usr/local/sbin/update-game-server || ! -f /etc/steamfoundry.conf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  msg_info "Updating Game Server"

  if $STD /usr/local/sbin/update-game-server; then
    msg_ok "Updated Game Server"
  else
    msg_error "Failed to Update Game Server"
    exit 1
  fi

  exit 0
}

prompt_required() {
  local variable_name="$1"
  local prompt_text="$2"
  local entered_value=""

  while [[ -z "$entered_value" ]]; do
    read -r -p "${prompt_text}: " entered_value
  done

  printf -v "$variable_name" '%s' "$entered_value"
}

start

prompt_required \
  STEAMFOUNDRY_APP_ID \
  "Steam App ID"

prompt_required \
  STEAMFOUNDRY_START_EXEC \
  "Startup executable, relative to /opt/game-server"

read -r -p \
  "Startup arguments (optional): " \
  STEAMFOUNDRY_START_ARGS

if ! [[ "$STEAMFOUNDRY_APP_ID" =~ ^[0-9]+$ ]]; then
  msg_error "Steam App ID must be numeric."
  exit 1
fi

# Accept either FactoryServer.sh or ./FactoryServer.sh.
STEAMFOUNDRY_START_EXEC="${STEAMFOUNDRY_START_EXEC#./}"

# Do not permit the startup path to escape /opt/game-server.
case "$STEAMFOUNDRY_START_EXEC" in
  /* | ../* | */../* | */..)
    msg_error "Startup executable must remain inside /opt/game-server."
    exit 1
    ;;
esac

export STEAMFOUNDRY_APP_ID
export STEAMFOUNDRY_START_EXEC
export STEAMFOUNDRY_START_ARGS

build_container
description

msg_ok "Game server LXC created successfully."
