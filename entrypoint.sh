#!/bin/bash
# entrypoint.sh for Rust Server with Node.js Wrapper

# Rust App ID
SRCDS_APPID=258550

# Set SteamCMD home directory.
export HOME="/home/container"

# Define the full path to the SteamCMD executable.
STEAMCMD_PATH="/home/container/steamcmd/steamcmd.sh"

# File to store the last installed branch to detect changes.
INSTALLED_BRANCH_FILE="/home/container/.installed_branch"

echo "Starting Pterodactyl entrypoint script..."

# Read the internal Docker IP address.
export INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')

# Read the current branch from the environment variable. Default to 'release'.
CURRENT_BRANCH="${BRANCH:-release}"
echo "Configured Rust Branch: ${CURRENT_BRANCH}"

# Read the last installed branch from the flag file.
LAST_INSTALLED_BRANCH=""
if [ -f "${INSTALLED_BRANCH_FILE}" ]; then
    LAST_INSTALLED_BRANCH=$(cat "${INSTALLED_BRANCH_FILE}")
    echo "Last installed Branch detected: ${LAST_INSTALLED_BRANCH}"
fi

# --- Re-installation Trigger Logic ---
if [ "${LAST_INSTALLED_BRANCH}" != "${CURRENT_BRANCH}" ] || [ ! -f "${STEAMCMD_PATH}" ]; then
    if [ -n "${LAST_INSTALLED_BRANCH}" ] && [ "${LAST_INSTALLED_BRANCH}" != "${CURRENT_BRANCH}" ]; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "!!! Branch change detected: '${LAST_INSTALLED_BRANCH}' -> '${CURRENT_BRANCH}' !!!"
        echo "!!! Forcing a complete re-installation of server files. !!!"
        echo "!!! Deleting all files in /home/container to trigger Pterodactyl's install script. !!!"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        rm -rf /home/container/*
        exit 1 # Exit with error to trigger Pterodactyl's reinstall mechanism
    elif [ ! -f "${STEAMCMD_PATH}" ]; then
        echo "SteamCMD executable not found. This indicates a fresh installation or a corrupted one."
        echo "Proceeding with SteamCMD installation/update from entrypoint."
    fi
fi

# Write the current branch to the file so we can detect future changes.
echo "${CURRENT_BRANCH}" > "${INSTALLED_BRANCH_FILE}"

# Dynamically set the SteamCMD branch flag.
BRANCH_FLAG=""
if [ "${CURRENT_BRANCH}" != "release" ]; then
    BRANCH_FLAG="-beta ${CURRENT_BRANCH}"
fi

# SteamCMD login details.
STEAM_USER=${STEAM_USER:-anonymous}
STEAM_PASS=${STEAM_PASS:-""}
STEAM_AUTH=${STEAM_AUTH:-""}

# Auto-update logic
if [ -z "${AUTO_UPDATE}" ] || [ "${AUTO_UPDATE}" == "1" ]; then
    echo "Updating Rust server files for branch '${CURRENT_BRANCH}' (AppID: ${SRCDS_APPID})..."

    CURRENT_DIR=$(pwd)
    cd /home/container/steamcmd || { echo "ERROR: Cannot change to SteamCMD directory. Exiting."; exit 1; }

    ./steamcmd.sh +force_install_dir /home/container +login "${STEAM_USER}" "${STEAM_PASS}" "${STEAM_AUTH}" +app_update "${SRCDS_APPID}" ${BRANCH_FLAG} validate +quit

    if [ $? -ne 0 ]; then
        echo "ERROR: SteamCMD update failed! Check logs for details."
        cd "${CURRENT_DIR}"
        exit 1
    fi
    echo "Rust server files updated successfully."
    cd "${CURRENT_DIR}"
else
    echo "Not updating game server as AUTO_UPDATE was set to 0. Starting Server."
fi

# Permissions anpassen
echo "Setting correct file permissions for /home/container (Rust game files)..."
chmod -R u+rwX /home/container

# Prepare the startup command for the Node.js wrapper
MODIFIED_STARTUP=$(eval echo "$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')")

echo "Server startup command: ${MODIFIED_STARTUP}"

# Modding Frameworks (Carbon/Oxide) logic
if [[ "${FRAMEWORK}" == "carbon" ]]; then
    echo "Updating Carbon..."
    curl -sSL "https://github.com/CarbonCommunity/Carbon.Core/releases/download/production_build/Carbon.Linux.Release.tar.gz" | tar zx
    echo "Done updating Carbon!"

    export DOORSTOP_ENABLED=1
    export DOORSTOP_TARGET_ASSEMBLY="$(pwd)/carbon/managed/Carbon.Preloader.dll"
    MODIFIED_STARTUP="LD_PRELOAD=$(pwd)/libdoorstop.so ${MODIFIED_STARTUP}"

elif [[ "$OXIDE" == "1" ]] || [[ "${FRAMEWORK}" == "oxide" ]]; then
    echo "Updating uMod..."
    curl -sSL "https://github.com/OxideMod/Oxide.Rust/releases/latest/download/Oxide.Rust-linux.zip" > umod.zip
    unzip -o -q umod.zip
    rm umod.zip
    echo "Done updating uMod!"
fi

# Fix for Rust not starting
# IMPORTANT: Added /home/container/.steam/sdk64 to the LD_LIBRARY_PATH
export LD_LIBRARY_PATH="/home/container/.steam/sdk64:$(pwd)/RustDedicated_Data/Plugins/x86_64:$(pwd)"

# Ensure RustDedicated is executable before trying to run it.
chmod +x ./RustDedicated || { echo "ERROR: Could not make RustDedicated executable. Exiting."; exit 1; }

echo "Running server via Node.js wrapper..."
exec node /wrapper.js "${MODIFIED_STARTUP}"
