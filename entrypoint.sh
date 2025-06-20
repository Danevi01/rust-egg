#!/bin/bash
# entrypoint.sh for Rust Server with Node.js Wrapper

# Rust App ID
SRCDS_APPID=258550

# Set SteamCMD home directory to avoid issues.
# This ensures SteamCMD writes its files (like SteamApps cache) correctly.
# SteamCMD is located in /home/container/steamcmd, so its HOME should be /home/container.
export HOME="/home/container"

# Define the full path to the SteamCMD executable.
# It's confirmed to be in /home/container/steamcmd/steamcmd.sh based on your previous output.
STEAMCMD_PATH="/home/container/steamcmd/steamcmd.sh"

# Check if the SteamCMD executable exists. If not, print an error and exit.
if [ ! -f "${STEAMCMD_PATH}" ]; then
    echo "ERROR: SteamCMD executable not found at ${STEAMCMD_PATH}!"
    echo "Please ensure your Pterodactyl Egg's installation script correctly installs SteamCMD."
    exit 1
fi

# Dynamically set the SteamCMD branch flag based on the Pterodactyl 'BRANCH' environment variable.
# If BRANCH is set and not "release", use the -beta flag. Otherwise, default to release.
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
# +force_install_dir /mnt/server tells SteamCMD to install the game files into the /mnt/server directory,
# which is Pterodactyl's designated persistent storage for game data.
# +app_update "${SRCDS_APPID}" uses the defined Rust App ID.
# ${BRANCH_FLAG} applies the selected branch (e.g., -beta staging).
# validate ensures file integrity and can repair corrupted files without full re-download.
# +quit ensures SteamCMD exits cleanly after the update.
./steamcmd.sh +force_install_dir /mnt/server +login "${STEAM_USER}" "${STEAM_PASS}" "${STEAM_AUTH}" +app_update "${SRCDS_APPID}" ${BRANCH_FLAG} validate +quit

# Check the exit status of SteamCMD. If it's not 0, an error occurred during the update.
if [ $? -ne 0 ]; then
    echo "ERROR: SteamCMD update failed! Check logs for details."
    exit 1
fi

echo "Rust server files updated successfully."

# --- NEUE ZEILEN FÜR BERECHTIGUNGEN ---
echo "Setting correct file permissions for /mnt/server..."
chown -R container:container /mnt/server
chmod -R u+rwX /mnt/server
# -----------------------------------

# --- Prepare the startup command for the Node.js wrapper ---
# Pterodactyl automatically replaces {{VARIABLE}} placeholders in the Egg's startup string
# with actual environment variables (e.g., $SERVER_PORT) before this script runs.
# Therefore, we use environment variables directly here to build the command.

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

# Ensure the /mnt/server directory exists. This is crucial as SteamCMD installs
# the game files here, and the server expects to run from this location.
mkdir -p /mnt/server

# Change the current directory to /mnt/server.
# The RustDedicated executable should be in this directory.
# The Node.js wrapper will be executed from here, and it will then launch RustDedicated
# relative to this path (e.g., ./RustDedicated).
cd /mnt/server || { echo "ERROR: Cannot change to server game directory. Exiting."; exit 1; }

echo "Starting server via Node.js wrapper: node /wrapper.js \"${MODIFIED_STARTUP}\""

# Execute the Node.js wrapper with the generated startup command.
# Using 'exec' ensures that the Node.js process takes over PID 1, allowing for proper
# signal handling (e.g., stopping the container gracefully).
# Ensure 'node' is in the container's PATH and '/wrapper.js' is the correct path to your wrapper.
exec node /wrapper.js "${MODIFIED_STARTUP}"
