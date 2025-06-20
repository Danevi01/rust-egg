#!/bin/bash
# entrypoint.sh for Rust Server with Node.js Wrapper

# Rust App ID
SRCDS_APPID=258550

# Set SteamCMD home directory to avoid issues
export HOME=/mnt/server

# Ensure SteamCMD is executable and in the correct place
# This assumes SteamCMD was installed by the egg's installation script
STEAMCMD_PATH="/mnt/server/steamcmd/steamcmd.sh"

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
cd /mnt/server/steamcmd || exit 1 # Change to steamcmd directory

# Run SteamCMD update
# Use +quit to ensure steamcmd exits after update
# The 'validate' flag ensures file integrity and can fix corrupted files
./steamcmd.sh +force_install_dir /mnt/server +login "${STEAM_USER}" "${STEAM_PASS}" "${STEAM_AUTH}" +app_update "${SRCDS_APPID}" ${BRANCH_FLAG} validate +quit

# Check if SteamCMD update was successful
if [ $? -ne 0 ]; then
    echo "ERROR: SteamCMD update failed! Check logs for details."
    exit 1
fi

echo "Rust server files updated successfully."

# --- Prepare startup command for the Node.js wrapper ---
# Build the exact startup command string that the wrapper expects
# This should match your egg's 'startup' field, but without the initial '.\/RustDedicated'
# as the wrapper likely handles execution.

MODIFIED_STARTUP="./RustDedicated -batchmode"
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.port {{SERVER_PORT}}"
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.queryport {{QUERY_PORT}}"
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.identity \"rust\""
MODIFIED_STARTUP="${MODIFIED_STARTUP} +rcon.port {{RCON_PORT}}"
MODIFIED_STARTUP="${MODIFIED_STARTUP} +rcon.web true"
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.hostname \"{{HOSTNAME}}\""
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.level \"{{LEVEL}}\""
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.description \"{{DESCRIPTION}}\""
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.url \"{{SERVER_URL}}\""
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.headerimage \"{{SERVER_IMG}}\""
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.logoimage \"{{SERVER_LOGO}}\""
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.maxplayers {{MAX_PLAYERS}}"
MODIFIED_STARTUP="${MODIFIED_STARTUP} +rcon.password \"{{RCON_PASS}}\""
MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.saveinterval {{SAVEINTERVAL}}"
MODIFIED_STARTUP="${MODIFIED_STARTUP} +app.port {{APP_PORT}}"

# Add map URL or world size/seed logic as in your original egg's startup string
if [ -z "${MAP_URL}" ]; then
    MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.worldsize \"{{WORLD_SIZE}}\" +server.seed \"{{WORLD_SEED}}\""
else
    MODIFIED_STARTUP="${MODIFIED_STARTUP} +server.levelurl {{MAP_URL}}"
fi

# Add additional arguments
if [ -n "${ADDITIONAL_ARGS}" ]; then
    MODIFIED_STARTUP="${MODIFIED_STARTUP} ${ADDITIONAL_ARGS}"
fi

# IMPORTANT: Replace Pterodactyl's template variables with actual environment variables
# Pterodactyl replaces these placeholders BEFORE the entrypoint.sh is executed.
# The `startup` string in your egg should already do this,
# so the actual values will be substituted when the entrypoint runs.
# However, if your wrapper expects the raw template (e.g., {{SERVER_PORT}}), you might need to adjust.
# Assuming the Pterodactyl daemon already replaced them, we pass the built string.

# Ensure we are in the server directory before executing the wrapper
cd /mnt/server || exit 1

echo "Starting server via Node.js wrapper: node /wrapper.js \"${MODIFIED_STARTUP}\""

# Run the Node.js wrapper with the generated startup command
node /wrapper.js "${MODIFIED_STARTUP}"
