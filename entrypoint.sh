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

# --- UNTERSTÜTZTE: Logik für Neuinstallation bei Branch-Wechsel oder fehlendem SteamCMD ---
# Dies wird immer ausgeführt, wenn ein Branch-Wechsel erkannt wird ODER SteamCMD fehlt.
# Es stellt sicher, dass die korrekte Branch installiert ist.
if [ "${LAST_INSTALLED_BRANCH}" != "${CURRENT_BRANCH}" ] || [ ! -f "${STEAMCMD_PATH}" ]; then
    if [ -n "${LAST_INSTALLED_BRANCH}" ] && [ "${LAST_INSTALLED_BRANCH}" != "${CURRENT_BRANCH}" ]; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "!!! Branch change detected: '${LAST_INSTALLED_BRANCH}' -> '${CURRENT_BRANCH}' !!!"
        echo "!!! Forcing a complete re-installation of server files via SteamCMD in entrypoint.sh. !!!"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    elif [ ! -f "${STEAMCMD_PATH}" ]; then
        echo "SteamCMD executable not found. This indicates a fresh installation or a corrupted one."
        echo "Proceeding with SteamCMD installation/update from entrypoint."
    fi

    echo "Ensuring SteamCMD is installed and up-to-date..."
    mkdir -p /home/container/steamcmd # Sicherstellen, dass das Verzeichnis existiert
    CURRENT_DIR=$(pwd)
    cd /home/container/steamcmd || { echo "ERROR: Cannot change to SteamCMD directory. Exiting."; exit 1; }
    curl -sqL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - # Sicherstellen, dass SteamCMD vorhanden ist

    echo "Executing SteamCMD update/install for branch '${CURRENT_BRANCH}' (AppID: ${SRCDS_APPID})..."
    ./steamcmd.sh +force_install_dir /home/container +login "${STEAM_USER}" "${STEAM_PASS}" "${STEAM_AUTH}" +app_update "${SRCDS_APPID}" ${BRANCH_FLAG} validate +quit

    if [ $? -ne 0 ]; then
        echo "ERROR: SteamCMD update failed during forced re-installation! Exiting."
        cd "${CURRENT_DIR}"
        exit 1
    fi
    echo "SteamCMD forced update/install completed successfully."
    cd "${CURRENT_DIR}"

    # Wichtig: Kopiere die SteamSDK-Dateien an den richtigen Ort NACH der Installation.
    echo "Copying SteamSDK files..."
    mkdir -p /home/container/.steam/sdk32
    cp -v /home/container/steamcmd/linux32/steamclient.so /home/container/.steam/sdk32/steamclient.so
    mkdir -p /home/container/.steam/sdk64
    cp -v /home/container/steamcmd/linux64/steamclient.so /home/container/.steam/sdk64/steamclient.so
    echo "SteamSDK files copied."

    # Schreibe die aktuelle Branch in die Datei, NACHDEM die Installation abgeschlossen ist.
    # Dies verhindert einen weiteren Re-Install-Loop beim nächsten Start.
    echo "${CURRENT_BRANCH}" > "${INSTALLED_BRANCH_FILE}"

else # Wenn kein Branch-Wechsel ODER fehlendes SteamCMD erkannt wurde, fahren wir normal fort (optionales Update).
    echo "No branch change detected or SteamCMD already present. Proceeding with normal server startup."
    # Auto-update logic (Dieser Block wird weiterhin für normale Updates verwendet, wenn AUTO_UPDATE = 1)
    if [ -z "${AUTO_UPDATE}" ] || [ "${AUTO_UPDATE}" == "1" ]; then
        echo "Performing standard Rust server file update for branch '${CURRENT_BRANCH}' (AppID: ${SRCDS_APPID})..."

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
fi

# Permissions anpassen
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
# This converts Pterodactyl-style {{VAR}} to shell-style ${VAR} and substitutes.
# We also handle the double-quoting issue for RCON_PASS and HOSTNAME
# by removing redundant quotes from the template.

# Remove the extra quotes from RCON_PASS and HOSTNAME in the STARTUP string for correct parsing
CLEAN_STARTUP="${STARTUP}"
CLEAN_STARTUP="${CLEAN_STARTUP//\"{{RCON_PASS}}\"/{{RCON_PASS}}}" # Remove literal \" and \"
CLEAN_STARTUP="${CLEAN_STARTUP//\"{{HOSTNAME}}\"/{{HOSTNAME}}}" # Remove literal \" and \"
CLEAN_STARTUP="${CLEAN_STARTUP//\"{{DESCRIPTION}}\"/{{DESCRIPTION}}}" # Remove literal \" and \"
# Add other variables if they also use escaped quotes
CLEAN_STARTUP="${CLEAN_STARTUP//\"{{LEVEL}}\"/{{LEVEL}}}" # Added for consistency
CLEAN_STARTUP="${CLEAN_STARTUP//\"{{SERVER_IMG}}\"/{{SERVER_IMG}}}" # Added for consistency
CLEAN_STARTUP="${CLEAN_STARTUP//\"{{SERVER_LOGO}}\"/{{SERVER_LOGO}}}" # Added for consistency


# Now, perform the substitution to shell variables.
# This replaces {{VAR}} with the actual value of $VAR.
# We explicitly re-add quotes for variables that *should* have quotes around them.
FINAL_STARTUP=$(echo "${CLEAN_STARTUP}" \
    | sed -e "s|{{SERVER_PORT}}|${SERVER_PORT}|g" \
    -e "s|{{RCON_PORT}}|${RCON_PORT}|g" \
    -e "s|{{RCON_PASS}}|\"${RCON_PASS}\"|g" \
    -e "s|{{HOSTNAME}}|\"${HOSTNAME}\"|g" \
    -e "s|{{LEVEL}}|\"${LEVEL}\"|g" \
    -e "s|s|{{SERVER_IMG}}|\"${SERVER_IMG}\"|g" \
    -e "s|{{SERVER_LOGO}}|\"${SERVER_LOGO}\"|g" \
    -e "s|{{WORLD_SEED}}|${WORLD_SEED}|g" \
    -e "s|{{WORLD_SIZE}}|${WORLD_SIZE}|g" \
    -e "s|{{MAX_PLAYERS}}|${MAX_PLAYERS}|g" \
    -e "s|{{DESCRIPTION}}|\"${DESCRIPTION}\"|g" \
    -e "s|{{SERVER_URL}}|${SERVER_URL}|g" \
    -e "s|{{SAVEINTERVAL}}|${SAVEINTERVAL}|g" \
    -e "s|{{APP_PORT}}|${APP_PORT}|g" \
    -e "s|{{ADDITIONAL_ARGS}}|${ADDITIONAL_ARGS}|g" \
)

echo "Server startup command (after substitution): ${FINAL_STARTUP}"
echo "Running server via Node.js wrapper..."

# Execute the Node.js wrapper with the fully substituted command.
# Use eval to handle proper argument splitting based on quotes within FINAL_STARTUP.
eval exec "${FINAL_STARTUP}"
