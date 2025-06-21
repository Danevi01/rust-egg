#!/bin/bash
# entrypoint.sh for Rust Server with Node.js Wrapper

# Rust App ID
SRCDS_APPID=258550

# Set SteamCMD home directory.
export HOME="/home/container"

# Define the full path to the SteamCMD executable.
# Based on your existing setup, it's expected in /home/container/steamcmd.
STEAMCMD_PATH="/home/container/steamcmd/steamcmd.sh"

# File to store the last installed branch to detect changes.
INSTALLED_BRANCH_FILE="/home/container/.installed_branch"

echo "Starting Pterodactyl entrypoint script..."

# Read the current branch from the environment variable.
CURRENT_BRANCH="${BRANCH:-release}" # Default to 'release' if BRANCH is not set
echo "Configured Branch for this startup: ${CURRENT_BRANCH}"

# Read the last installed branch from the flag file.
LAST_INSTALLED_BRANCH=""
if [ -f "${INSTALLED_BRANCH_FILE}" ]; then
    LAST_INSTALLED_BRANCH=$(cat "${INSTALLED_BRANCH_FILE}")
    echo "Last installed Branch detected: ${LAST_INSTALLED_BRANCH}"
fi

# Logic to trigger a re-installation if the branch has changed.
# This ensures that the correct game files for the selected branch are always present.
# We also check if STEAMCMD_PATH doesn't exist, which implies a fresh install or a broken one.
if [ "${LAST_INSTALLED_BRANCH}" != "${CURRENT_BRANCH}" ] || [ ! -f "${STEAMCMD_PATH}" ]; then
    if [ -n "${LAST_INSTALLED_BRANCH}" ] && [ "${LAST_INSTALLED_BRANCH}" != "${CURRENT_BRANCH}" ]; then
        echo "Detected Branch change from '${LAST_INSTALLED_BRANCH}' to '${CURRENT_BRANCH}'."
        echo "Forcing a complete re-installation of server files to ensure branch consistency."
        echo "Deleting all files in /home/container to trigger Pterodactyl's install script."
        rm -rf /home/container/*
        exit 1 # Exit with error to trigger Pterodactyl's reinstall mechanism
    elif [ ! -f "${STEAMCMD_PATH}" ]; then
        echo "SteamCMD not found at ${STEAMCMD_PATH}. This indicates a fresh installation or a corrupted one."
        echo "Proceeding with SteamCMD installation/update."
    fi
fi

# Write the current branch to the file so we can detect future changes.
# This happens AFTER the re-install check, so if a reinstall is triggered,
# this file is deleted and written fresh after the new installation.
echo "${CURRENT_BRANCH}" > "${INSTALLED_BRANCH_FILE}"

# Dynamically set the SteamCMD branch flag based on the Pterodactyl 'BRANCH' environment variable.
BRANCH_FLAG=""
if [ "${CURRENT_BRANCH}" != "release" ]; then
    BRANCH_FLAG="-beta ${CURRENT_BRANCH}"
fi

# SteamCMD login details. Use 'anonymous' if STEAM_USER is not provided.
STEAM_USER=${STEAM_USER:-anonymous}
STEAM_PASS=${STEAM_PASS:-""}
STEAM_AUTH=${STEAM_AUTH:-""}

echo "Updating Rust server files for branch '${CURRENT_BRANCH}' (AppID: ${SRCDS_APPID})..."

# Change the current directory to where SteamCMD's executable is located before running it.
# This assumes your Egg's installation script correctly places steamcmd.sh into /home/container/steamcmd.
cd /home/container/steamcmd || { echo "ERROR: Cannot change to SteamCMD directory. Exiting."; exit 1; }

# Execute SteamCMD to update the Rust server files.
# +force_install_dir /home/container tells SteamCMD to install the game files into the /home/container directory.
./steamcmd.sh +force_install_dir /home/container +login "${STEAM_USER}" "${STEAM_PASS}" "${STEAM_AUTH}" +app_update "${SRCDS_APPID}" ${BRANCH_FLAG} validate +quit

# Check if SteamCMD update was successful
if [ $? -ne 0 ]; then
    echo "ERROR: SteamCMD update failed! Check logs for details."
    exit 1
fi

echo "Rust server files updated successfully."

# Permissions: Ensure 'container' user has write access in the directory.
# This is crucial because SteamCMD might download files as 'root' during installation.
echo "Setting correct file permissions for /home/container (Rust game files)..."
chown -R container:container /home/container || { echo "WARNING: Failed to set ownership for /home/container. Permissions might be an issue."; }
chmod -R u+rwX /home/container

# Prepare the startup command for the Node.js wrapper
MODIFIED_STARTUP=`eval echo $(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')`
# Assuming you want to keep the Node.js wrapper, the startup variable is passed to it.
# The original egg uses `node /wrapper.js "${MODIFIED_STARTUP}"`

echo ":/home/container$ ${MODIFIED_STARTUP}"

if [[ "${FRAMEWORK}" == "carbon" ]]; then
    # Carbon: https://github.com/CarbonCommunity/Carbon.Core
    echo "Updating Carbon..."
    curl -sSL "https://github.com/CarbonCommunity/Carbon.Core/releases/download/production_build/Carbon.Linux.Release.tar.gz" | tar zx
    echo "Done updating Carbon!"

    export DOORSTOP_ENABLED=1
    export DOORSTOP_TARGET_ASSEMBLY="$(pwd)/carbon/managed/Carbon.Preloader.dll"
    MODIFIED_STARTUP="LD_PRELOAD=$(pwd)/libdoorstop.so ${MODIFIED_STARTUP}"

elif [[ "$OXIDE" == "1" ]] || [[ "${FRAMEWORK}" == "oxide" ]]; then
    # Oxide: https://github.com/OxideMod/Oxide.Rust
    echo "Updating uMod..."
    curl -sSL "https://github.com/OxideMod/Oxide.Rust/releases/latest/download/Oxide.Rust-linux.zip" > umod.zip
    unzip -o -q umod.zip
    rm umod.zip
    echo "Done updating uMod!"
# else Vanilla, do nothing
fi

# Fix for Rust not starting (original from your entrypoint)
export LD_LIBRARY_PATH=$(pwd)/RustDedicated_Data/Plugins/x86_64:$(pwd)

# Run the Server via Node.js wrapper.
# Ensure RustDedicated is executable.
chmod +x ./RustDedicated || { echo "ERROR: Could not make RustDedicated executable. Exiting."; exit 1; }

echo "Running server command: ${MODIFIED_STARTUP}"
exec node /wrapper.js "${MODIFIED_STARTUP}"
