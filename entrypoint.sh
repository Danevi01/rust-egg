#!/bin/bash
# entrypoint.sh for Rust Server with Node.js Wrapper

# Rust App ID
SRCDS_APPID=258550

# Set SteamCMD home directory to avoid issues.
# This ensures SteamCMD writes its files (like SteamApps cache) correctly.
# SteamCMD is located in /home/container/steamcmd, so its HOME should be /home/container.
export HOME="/home/container"

# Define the full path to the SteamCMD executable.
# It's confirmed to be in /home/container/steamcmd/steamcmd.sh.
STEAMCMD_PATH="/home/container/steamcmd/steamcmd.sh"

# Check if the SteamCMD executable exists. If not, print an error and exit.
if [ ! -f "${STEAMCMD_PATH}" ]; then
    echo "ERROR: SteamCMD executable not found at ${STEAMCMD_PATH}!"
    echo "Please ensure your Pterodactyl Egg's installation script correctly installs SteamCMD."
    exit 1
fi

# Dynamically set the SteamCMD branch flag based on the Pterodactyl 'BRANCH' environment variable.
BRANCH_FLAG=""
if [ -n "${BRANCH}" ] && [ "${BRANCH}" != "release" ]; then
    echo "Selected Rust Branch: ${BRANCH}"
    BRANCH_FLAG="-beta ${BRANCH}"
else
    echo "Selected Rust Branch: release (default)"
fi

# SteamCMD login details. Use 'anonymous' if STEAM_USER is not provided.
STEAM_USER=${STEAM_USER:-anonymous}
STEAM_PASS=${STEAM_PASS:-""}
STEAM_AUTH=${STEAM_AUTH:-""}

echo "Updating Rust server files for branch '${BRANCH}' (AppID: ${SRCDS_APPID})..."

# Change the current directory to where SteamCMD's executable is located before running it.
cd /home/container/steamcmd || { echo "ERROR: Cannot change to SteamCMD directory. Exiting."; exit 1; }

# Execute SteamCMD to update the Rust server files.
# --- WICHTIGE ÄNDERUNG HIER: force_install_dir ist jetzt /home/container ---
./steamcmd.sh +force_install_dir /home/container +login "${STEAM_USER}" "${STEAM_PASS}" "${STEAM_AUTH}" +app_update "${SRCDS_APPID}" ${BRANCH_FLAG} validate +quit

# Check if SteamCMD update was successful
if [ $? -ne 0 ]; then
    echo "ERROR: SteamCMD update failed! Check logs for details."
    exit 1
fi

echo "Rust server files updated successfully."

# --- BERECHTIGUNGEN: WERDEN JETZT FÜR /home/container GESETZT ---
# Dies ist notwendig, da SteamCMD die Dateien als 'root' herunterlädt,
# der Server aber als 'container' Benutzer laufen muss.
echo "Setting correct file permissions for /home/container (Rust game files)..."
chown -R container:container /home/container
chmod -R u+rwX /home/container
# -----------------------------------

# --- Prepare the startup command for the Node.js wrapper ---
# Pterodactyl automatically replaces {{VARIABLE}} placeholders with actual environment variables.

MODIFIED_STARTUP="./RustDedicated -batchmode"
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.port ${SERVER_PORT}"
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.queryport ${QUERY_PORT}"
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.identity \"rust\""
MODIFIED_STARTUP="${MODIFIED_STARTUP} +rcon.port ${RCON_PORT}"
MODIFIED_STARTUP="${MODIFIED_STARTUP} +rcon.web true"
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.hostname \"${HOSTNAME}\""
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.level \"${LEVEL}\""
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.description \"${DESCRIPTION}\""
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.url \"${SERVER_URL}\""
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.headerimage \"${SERVER_IMG}\""
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.logoimage \"${SERVER_LOGO}\""
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.maxplayers ${MAX_PLAYERS}"
MODIFIED_STARTUP="${MODIFIED_STARTUP} +rcon.password \"${RCON_PASS}\""
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.saveinterval ${SAVEINTERVAL}"
MODIFIED_STARTUP="${MODIFIED_STARTUP} +app.port ${APP_PORT}"

# Conditional logic for map URL or world size/seed.
if [ -z "${MAP_URL}" ]; then
    MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.worldsize \"${WORLD_SIZE}\" +server.seed \"${WORLD_SEED}\""
else
    MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.levelurl ${MAP_URL}"
fi

# Append any additional arguments provided by the user.
if [ -n "${ADDITIONAL_ARGS}" ]; then
    MODIFIED_STARTUP="${MODIFIED_STARTUP} ${ADDITIONAL_ARGS}"
fi

# --- WICHTIGE ÄNDERUNG HIER: KEIN mkdir -p /mnt/server MEHR. cd jetzt nach /home/container ---
# Wechseln Sie in das Verzeichnis, in dem die Rust-Spieldateien liegen sollen.
# Da SteamCMD jetzt nach /home/container installiert, ist dies unser Arbeitsverzeichnis.
cd /home/container || { echo "ERROR: Cannot change to server game directory. Exiting."; exit 1; }

echo "Starting server via Node.js wrapper: node /wrapper.js \"${MODIFIED_STARTUP}\""

# Execute the Node.js wrapper with the generated startup command.
exec node /wrapper.js "${MODIFIED_STARTUP}"
