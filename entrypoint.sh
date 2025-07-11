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

# Dynamically set the SteamCMD branch flag based on CURRENT_BRANCH.
BRANCH_FLAG=""
if [ "${CURRENT_BRANCH}" != "release" ]; then
    BRANCH_FLAG="-beta ${CURRENT_BRANCH}"
fi

# SteamCMD login details.
STEAM_USER=${STEAM_USER:-anonymous}
STEAM_PASS=${STEAM_PASS:-""}
STEAM_AUTH=${STEAM_AUTH:-""}


# --- Funktion zum vollständigen Löschen aller Serverdaten ---
clean_all_server_data() {
    echo "WARNING: Deleting ALL server data (including maps, saves, and configuration files) to ensure a clean branch installation."
    local temp_branch_content=""
    if [ -f "${INSTALLED_BRANCH_FILE}" ]; then
        temp_branch_content=$(cat "${INSTALLED_BRANCH_FILE}")
        echo "Temporarily saving .installed_branch content: ${temp_branch_content}"
    fi

    echo "Deleting all contents of ${HOME}..."
    rm -rf "${HOME}"/* # Löscht alle nicht-versteckten Dateien und Verzeichnisse
    rm -rf "${HOME}"/.[!.]* # Löscht alle versteckten Dateien und Verzeichnisse (außer '.' und '..')
    echo "All old server data removed from ${HOME}."

    if [ -n "${temp_branch_content}" ]; then
        echo "${temp_branch_content}" > "${INSTALLED_BRANCH_FILE}"
        echo "Restored .installed_branch content (will be updated later)."
    fi
}
# --- Ende Funktion ---


# --- Hauptlogik für Installation / Update ---
SHOULD_PERFORM_UPDATE=0

if [ "${LAST_INSTALLED_BRANCH}" != "${CURRENT_BRANCH}" ]; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!!! Branch change detected: '${LAST_INSTALLED_BRANCH}' -> '${CURRENT_BRANCH}' !!!"
    clean_all_server_data # <-- HIER WIRD ALLES GELÖSCHT!
    echo "!!! Forcing a complete re-installation of server files via SteamCMD. !!!"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    SHOULD_PERFORM_UPDATE=1
elif [ ! -f "${STEAMCMD_PATH}" ]; then
    echo "SteamCMD executable not found. This indicates a fresh installation or a corrupted one."
    echo "Proceeding with SteamCMD installation/update from entrypoint."
    SHOULD_PERFORM_UPDATE=1
elif [ -z "${AUTO_UPDATE}" ] || [ "${AUTO_UPDATE}" == "1" ]; then
    echo "No branch change detected. Auto-update is enabled. Performing standard Rust server file update."
    SHOULD_PERFORM_UPDATE=1
else
    echo "Not updating game server as AUTO_UPDATE was set to 0. Starting Server without update."
    SHOULD_PERFORM_UPDATE=0
fi


if [ "${SHOULD_PERFORM_UPDATE}" -eq 1 ]; then
    echo "Ensuring SteamCMD is installed and up-to-date..."
    mkdir -p /home/container/steamcmd # Sicherstellen, dass das Verzeichnis existiert
    CURRENT_WORKING_DIR=$(pwd) # Aktuelles Arbeitsverzeichnis speichern
    cd /home/container/steamcmd || { echo "ERROR: Cannot change to SteamCMD directory. Exiting."; exit 1; }
    curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - # Sicherstellen, dass SteamCMD vorhanden ist

    echo "Executing SteamCMD update/install for branch '${CURRENT_BRANCH}' (AppID: ${SRCDS_APPID})..."
    ./steamcmd.sh +force_install_dir /home/container +login "${STEAM_USER}" "${STEAM_PASS}" "${STEAM_AUTH}" +app_update "${SRCDS_APPID}" ${BRANCH_FLAG} validate +quit

    if [ $? -ne 0 ]; then
        echo "ERROR: SteamCMD update failed! Check logs for details."
        cd "${CURRENT_WORKING_DIR}" # Zurück zum ursprünglichen Arbeitsverzeichnis
        exit 1
    fi
    echo "SteamCMD update/install completed successfully."
    cd "${CURRENT_WORKING_DIR}" # Zurück zum ursprünglichen Arbeitsverzeichnis

    echo "Copying SteamSDK files..."
    mkdir -p /home/container/.steam/sdk32
    cp -v /home/container/steamcmd/linux32/steamclient.so /home/container/.steam/sdk32/steamclient.so
    mkdir -p /home/container/.steam/sdk64
    cp -v /home/container/steamcmd/linux64/steamclient.so /home/container/.steam/sdk64/steamclient.so
    echo "SteamSDK files copied."

    echo "${CURRENT_BRANCH}" > "${INSTALLED_BRANCH_FILE}"
    echo "Updated .installed_branch to: ${CURRENT_BRANCH}"
fi

echo "Setting correct file permissions for /home/container (Rust game files)..."
chmod -R u+rwX /home/container

# Modding Frameworks (Carbon/Oxide) logic
if [[ "${FRAMEWORK}" == "carbon" ]]; then
    echo "Updating Carbon..."
    curl -sSL "https://github.com/CarbonCommunity/Carbon.Core/releases/download/production_build/Carbon.Linux.Release.tar.gz" | tar zx
    echo "Done updating Carbon!"

    export DOORSTOP_ENABLED=1
    export DOORSTOP_TARGET_ASSEMBLY="$(pwd)/carbon/managed/Carbon.Preloader.dll"
    export LD_PRELOAD="$(pwd)/libdoorstop.so"

elif [[ "$OXIDE" == "1" ]] || [[ "${FRAMEWORK}" == "oxide" ]]; then
    echo "Updating uMod..."
    curl -sSL "https://github.com/OxideMod/Oxide.Rust/releases/latest/download/Oxide.Rust-linux.zip" > umod.zip
    unzip -o -q umod.zip
    rm umod.zip
    echo "Done updating uMod!"
fi

# Fix for Rust not starting
export LD_LIBRARY_PATH="/home/container/.steam/sdk64:$(pwd)/RustDedicated_Data/Plugins/x86_64:$(pwd)"

# Ensure RustDedicated is executable.
chmod +x ./RustDedicated || { echo "ERROR: Could not make RustDedicated executable. Exiting."; exit 1; }

# --- Manual variable substitution for the startup command ---
# This logic replaces the Pterodactyl placeholders with their actual values.
# Variables like HOSTNAME and DESCRIPTION, which can contain spaces,
# are enclosed in double quotes for correct passing.
FINAL_STARTUP=$(echo "${STARTUP}" \
    | sed -e "s|{{SERVER_PORT}}|${SERVER_PORT}|g" \
    -e "s|{{RCON_PORT}}|${RCON_PORT}|g" \
    -e "s|{{RCON_PASS}}|\"${RCON_PASS}\"|g" \
    -e "s|{{HOSTNAME}}|\"${HOSTNAME}\"|g" \
    -e "s|{{LEVEL}}|\"${LEVEL}\"|g" \
    -e "s|{{WORLD_SEED}}|${WORLD_SEED}|g" \
    -e "s|{{WORLD_SIZE}}|${WORLD_SIZE}|g" \
    -e "s|{{MAX_PLAYERS}}|${MAX_PLAYERS}|g" \
    -e "s|{{DESCRIPTION}}|\"${DESCRIPTION}\"|g" \
    -e "s|{{SERVER_URL}}|${SERVER_URL}|g" \
    -e "s|{{SERVER_IMG}}|${SERVER_IMG}|g" \
    -e "s|{{SERVER_LOGO}}|${SERVER_LOGO}|g" \
    -e "s|{{SAVEINTERVAL}}|${SAVEINTERVAL}|g" \
    -e "s|{{APP_PORT}}|${APP_PORT}|g" \
    -e "s|{{ADDITIONAL_ARGS}}|${ADDITIONAL_ARGS}|g" \
)

# Handle MAP_URL separately: add +server.levelurl ONLY if MAP_URL is not empty
MAP_URL_ARG=""
if [ -n "${MAP_URL}" ]; then
    MAP_URL_ARG=" +server.levelurl \"${MAP_URL}\""
fi

# Append MAP_URL_ARG to FINAL_STARTUP
FINAL_STARTUP="${FINAL_STARTUP}${MAP_URL_ARG}"

echo "Server startup command (after substitution): ${FINAL_STARTUP}"
echo "Running server via Node.js wrapper..."

# Execute the Node.js wrapper with the fully substituted command.
# Use eval to handle proper argument splitting based on quotes within FINAL_STARTUP.
eval exec "${FINAL_STARTUP}"
