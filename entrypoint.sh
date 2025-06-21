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

# Read the internal Docker IP address.
export INTERNAL_IP=`ip route get 1 | awk '{print $(NF-2);exit}'`

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
# Trigger a re-installation if:
# 1. The configured branch has changed from the last installed one.
# 2. SteamCMD executable is not found (implies a fresh install or a corrupted one).
if [ "${LAST_INSTALLED_BRANCH}" != "${CURRENT_BRANCH}" ] || [ ! -f "${STEAMCMD_PATH}" ]; then
    if [ -n "${LAST_INSTALLED_BRANCH}" ] && [ "${LAST_INSTALLED_BRANCH}" != "${CURRENT_BRANCH}" ]; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "!!! Branch change detected: '${LAST_INSTALLED_BRANCH}' -> '${CURRENT_BRANCH}' !!!"
        echo "!!! Forcing a complete re-installation of server files. !!!"
        echo "!!! Deleting all files in /home/container to trigger Pterodactyl's install script. !!!"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        # Delete all files to force Pterodactyl to run the egg's installation script again.
        rm -rf /home/container/*
        exit 1 # Exit with error to trigger Pterodactyl's reinstall mechanism
    elif [ ! -f "${STEAMCMD_PATH}" ]; then
        echo "SteamCMD executable not found. This indicates a fresh installation or a corrupted one."
        echo "Proceeding with SteamCMD installation/update from entrypoint."
    fi
fi

# Write the current branch to the file so we can detect future changes.
# This happens AFTER the re-install check. If a reinstall was triggered,
# this file would have been deleted and will be written fresh after the new installation is complete.
echo "${CURRENT_BRANCH}" > "${INSTALLED_BRANCH_FILE}"

# Dynamically set the SteamCMD branch flag.
BRANCH_FLAG=""
if [ "${CURRENT_BRANCH}" != "release" ]; then
    BRANCH_FLAG="-beta ${CURRENT_BRANCH}"
fi

# SteamCMD login details. Use 'anonymous' if STEAM_USER is not provided.
STEAM_USER=${STEAM_USER:-anonymous}
STEAM_PASS=${STEAM_PASS:-""}
STEAM_AUTH=${STEAM_AUTH:-""}

# Auto-update logic (from your original entrypoint)
if [ -z "${AUTO_UPDATE}" ] || [ "${AUTO_UPDATE}" == "1" ]; then
    echo "Updating Rust server files for branch '${CURRENT_BRANCH}' (AppID: ${SRCDS_APPID})..."

    # Change the current directory to where SteamCMD's executable is located.
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
else
    echo "Not updating game server as AUTO_UPDATE was set to 0. Starting Server."
fi

---

# Permissions anpassen

**WICHTIG:** Da `chown` die "Operation not permitted"-Fehler verursacht hat, habe ich diesen Befehl entfernt. Wir verlassen uns nun darauf, dass das `chmod` ausreicht, um dem `container`-Benutzer Schreibrechte zu geben. Wenn die Dateien von `root` erstellt wurden, erlaubt `chmod` dem `container`-Benutzer, darauf zuzugreifen, ohne den Besitzer zu wechseln.

---

echo "Setting correct file permissions for /home/container (Rust game files)..."
# Removed chown command as it causes "Operation not permitted" error.
# We are relying solely on chmod for user access.
chmod -R u+rwX /home/container

# Prepare the startup command for the Node.js wrapper
# This uses the STARTUP variable from the Egg configuration.
MODIFIED_STARTUP=`eval echo $(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')`

echo "Server startup command: ${MODIFIED_STARTUP}"

# Modding Frameworks (Carbon/Oxide) logic from your original entrypoint
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

# Fix for Rust not starting (original from your entrypoint)
export LD_LIBRARY_PATH=$(pwd)/RustDedicated_Data/Plugins/x86_64:$(pwd)

# Ensure RustDedicated is executable before trying to run it.
chmod +x ./RustDedicated || { echo "ERROR: Could not make RustDedicated executable. Exiting."; exit 1; }

echo "Running server via Node.js wrapper..."
exec node /wrapper.js "${MODIFIED_STARTUP}"
