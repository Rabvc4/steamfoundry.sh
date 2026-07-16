#!/usr/bin/env bash

# Copyright (c) 2026 Ryan Best
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://developer.valvesoftware.com/wiki/SteamCMD

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"

color
verb_ip6
catch_errors

: "${STEAMFOUNDRY_APP_ID:?Steam App ID was not provided}"
: "${STEAMFOUNDRY_START_EXEC:?Startup executable was not provided}"

STEAMFOUNDRY_START_ARGS="${STEAMFOUNDRY_START_ARGS:-}"

setting_up_container
network_check
update_os

msg_info "Installing Dependencies"

$STD apt install -y \
  lib32gcc-s1 \
  lib32stdc++6

msg_ok "Installed Dependencies"

msg_info "Creating Application Directories"

mkdir -p /opt/game-server

msg_ok "Created Application Directories"

fetch_and_deploy_from_url \
  "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
  "/opt/steamcmd"

msg_info "Installing Steam App ${STEAMFOUNDRY_APP_ID}"

msg_info "Initializing SteamCMD"

$STD /opt/steamcmd/steamcmd.sh \
  +quit

msg_ok "Initialized SteamCMD"

msg_info "Installing Steam App ${STEAMFOUNDRY_APP_ID}"

install_succeeded=0

for attempt in 1 2 3; do
  if $STD /opt/steamcmd/steamcmd.sh \
    +force_install_dir /opt/game-server \
    +login anonymous \
    +app_update "$STEAMFOUNDRY_APP_ID" validate \
    +quit; then

    install_succeeded=1
    break
  fi

  if ((attempt < 3)); then
    msg_warn "SteamCMD install attempt ${attempt} failed; retrying in 15 seconds"
    sleep 15
  fi
done

if ((install_succeeded == 0)); then
  msg_error "Failed to install Steam App ${STEAMFOUNDRY_APP_ID} after 3 attempts"
  exit 1
fi

msg_ok "Installed Steam App ${STEAMFOUNDRY_APP_ID}"

msg_ok "Installed Steam App ${STEAMFOUNDRY_APP_ID}"

START_PATH="/opt/game-server/${STEAMFOUNDRY_START_EXEC#./}"

if [[ ! -e "$START_PATH" ]]; then
  msg_error "Startup executable was not found: $START_PATH"
  exit 1
fi

chmod +x "$START_PATH"

msg_info "Creating SteamFoundry Configuration"

{
  printf 'APP_ID=%q\n' \
    "$STEAMFOUNDRY_APP_ID"

  printf 'START_EXEC=%q\n' \
    "$STEAMFOUNDRY_START_EXEC"

  printf 'START_ARGS=%q\n' \
    "$STEAMFOUNDRY_START_ARGS"
} >/etc/steamfoundry.conf

chmod 0600 /etc/steamfoundry.conf

msg_ok "Created SteamFoundry Configuration"

msg_info "Creating Game Server Scripts"

cat >/usr/local/sbin/start-game-server <<'START_SCRIPT'
#!/usr/bin/env bash

set -Eeuo pipefail

source /etc/steamfoundry.conf

cd /opt/game-server

START_PATH="/opt/game-server/${START_EXEC#./}"

if [[ -n "$START_ARGS" ]]; then
  # START_ARGS is trusted administrator input stored in a root-only file.
  eval "set -- $START_ARGS"
  exec "$START_PATH" "$@"
else
  exec "$START_PATH"
fi
START_SCRIPT

chmod 0755 /usr/local/sbin/start-game-server

cat >/usr/local/sbin/update-game-server <<'UPDATE_SCRIPT'
#!/usr/bin/env bash

set -Eeuo pipefail

source /etc/steamfoundry.conf

update_server() {
  /opt/steamcmd/steamcmd.sh \
    +force_install_dir /opt/game-server \
    +login anonymous \
    +app_update "$APP_ID" \
    +quit
}

# Used by the boot-time updater before the game service starts.
if [[ "${1:-}" == "--install-only" ]]; then
  update_server
  exit 0
fi

was_active=0

if systemctl is-active --quiet game-server.service; then
  was_active=1
  systemctl stop game-server.service
fi

if update_server; then
  if ((was_active)); then
    systemctl start game-server.service
  fi
else
  exit_code=$?

  # Attempt to bring the server back after a failed update.
  if ((was_active)); then
    systemctl start game-server.service || true
  fi

  exit "$exit_code"
fi
UPDATE_SCRIPT

chmod 0755 /usr/local/sbin/update-game-server

msg_ok "Created Game Server Scripts"

msg_info "Creating Game Server Services"

cat >/etc/systemd/system/game-server-update.service <<'UPDATE_UNIT'
[Unit]
Description=Update Steam game server at container startup
Wants=network-online.target
After=network-online.target
Before=game-server.service
ConditionPathExists=!/run/game-server-skip-boot-update

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/update-game-server --install-only
RemainAfterExit=yes
UPDATE_UNIT

cat >/etc/systemd/system/game-server.service <<'GAME_UNIT'
[Unit]
Description=Steam Game Server
Wants=network-online.target game-server-update.service
After=network-online.target game-server-update.service

[Service]
Type=simple
User=root
Environment=HOME=/root
Environment=LANG=C.UTF-8
WorkingDirectory=/opt/game-server
ExecStart=/usr/local/sbin/start-game-server
Restart=on-failure
RestartSec=10
TimeoutStopSec=120
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
GAME_UNIT

systemctl daemon-reload
systemctl enable -q game-server.service

# The application was installed immediately above. Skip a duplicate update
# during this first service start. The marker disappears after an LXC reboot.
touch /run/game-server-skip-boot-update

systemctl start game-server.service

sleep 2

systemctl is-active --quiet game-server.service

msg_ok "Created Game Server Services"

motd_ssh
customize
cleanup_lxc
