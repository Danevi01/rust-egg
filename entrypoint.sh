#!/bin/bash
# entrypoint.sh for Rust Server with Node.js Wrapper

# Rust App ID
SRCDS_APPID=258550

# Set SteamCMD home directory to avoid issues.
# This ensures SteamCMD writes its files (like SteamApps cache) correctly.
export HOME="/home/container"

# Ensure SteamCMD is executable and in the correct place
STEAMCMD_PATH="/home/container/steamcmd/steamcmd.sh"

if [ ! -f "${STEAMCMD_PATH}" ]; then
    echo "ERROR: SteamCMD executable not found at ${STEAMCMD_PATH}!"
    echo "Please ensure your Pterodactyl Egg's installation script correctly installs SteamCMD."
    exit 1
fi

# Dynamically set the SteamCMD branch flag based on the Pterodactyl 'BRANCH' variable
BRANCH_FLAG=""
if [ -n "${BRANCH}" ] && [ "${BRANCH}" != "release" ]; then
    echo "Selected Rust Branch: ${BRANCH}"
    BRANCH_FLAG="-beta ${BRANCH}"
else
    echo "Selected Rust Branch: release (default)"
fi

# SteamCMD login - use anonymous if STEAM_USER is not set
STEAM_USER=${STEAM_USER:-anonymous}
STEAM_PASS=${STEAM_PASS:-""}
STEAM_AUTH=${STEAM_AUTH:-""}

echo "Updating Rust server files for branch '${BRANCH}' (AppID: ${SRCDS_APPID})..."

# Change to SteamCMD directory to run steamcmd.sh
# Ensure we are running from the directory where steamcmd.sh is located
cd /home/container/steamcmd || { echo "ERROR: Cannot change to SteamCMD directory. Exiting."; exit 1; }

# Run SteamCMD update
# Use +quit to ensure steamcmd exits after update
# The 'validate' flag ensures file integrity and can fix corrupted files
# Force install dir to /mnt/server, as this is where Rust game files should be.
./steamcmd.sh +force_install_dir /mnt/server +login "${STEAM_USER}" "${STEAM_PASS}" "${STEAM_AUTH}" +app_update "${SRCDS_APPID}" ${BRANCH_FLAG} validate +quit

# Check if SteamCMD update was successful
if [ $? -ne 0 ]; then
    echo "ERROR: SteamCMD update failed! Check logs for details."
    exit 1
fi

echo "Rust server files updated successfully."

# --- Prepare startup command for the Node.js wrapper ---
# Build the exact startup command string that the wrapper expects.
# Pterodactyl replaces {{VARIABLE}} placeholders with actual environment variables
# before the entrypoint.sh runs. So, we use $VARIABLE here.

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

# Add map URL or world size/seed logic
if [ -z "${MAP_URL}" ]; then
    MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.worldsize \"${WORLD_SIZE}\" +server.seed \"${WORLD_SEED}\""
else
    MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.levelurl ${MAP_URL}"
fi

# Add additional arguments
if [ -n "${ADDITIONAL_ARGS}" ]; then
    MODIFIED_STARTUP="${MODIFIED_STARTUP} ${ADDITIONAL_ARGS}"
fi

# Ensure we are in the server directory (/mnt/server) before executing the wrapper.
# The RustDedicated executable should be in /mnt/server.
# The Node.js wrapper itself might be in /home/container or / (depending on your Dockerfile).
# It's safest to cd into /mnt/server before running the wrapper,
# assuming the wrapper then executes RustDedicated relative to that path.
cd /mnt/server || { echo "ERROR: Cannot change to server game directory. Exiting."; exit 1; }

echo "Starting server via Node.js wrapper: node /wrapper.js \"${MODIFIED_STARTUP}\""

# Run the Node.js wrapper with the generated startup command.
# Ensure 'node' executable is in the PATH within your Docker image.
# Ensure '/wrapper.js' is the correct path to your wrapper script in the container.
exec node /wrapper.js "${MODIFIED_STARTUP}"
