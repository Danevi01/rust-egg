#!/bin/bash
cd /home/container

# Make internal Docker IP address available to processes.
export INTERNAL_IP=`ip route get 1 | awk '{print $(NF-2);exit}'`

# Ensure the .steam/sdk64 directory exists for steamclient.so
mkdir -p "$HOME/.steam/sdk64"

## if auto_update is not set or to 1 update
if [ -z ${AUTO_UPDATE} ] || [ "${AUTO_UPDATE}" == "1" ]; then
    echo "Starting SteamCMD update for Rust server..."
    # Perform the SteamCMD update. The +quit is essential.
    # We use /usr/games/steamcmd as per typical Debian installation,
    # assuming it's correctly linked or in PATH after apt install.
    # If steamcmd is in a specific folder like /home/container/steamcmd/steamcmd.sh, use that path instead.
    /usr/games/steamcmd +force_install_dir "$HOME" +login anonymous +app_update 258550 -beta "${BRANCH}" +quit
    echo "SteamCMD update complete."

    # After update, ensure steamclient.so is linked correctly and LD_LIBRARY_PATH is set
    # The find command will locate steamclient.so (often put in ~/.steam/sdk64 by SteamCMD itself
    # or somewhere else within the installed game directory)
    STEAMCLIENT_PATH=$(find "$HOME" -name "steamclient.so" -print -quit)
    if [ -n "$STEAMCLIENT_PATH" ]; then
        ln -sf "$STEAMCLIENT_PATH" "$HOME/.steam/sdk64/steamclient.so"
        echo "Linked steamclient.so from $STEAMCLIENT_PATH to $HOME/.steam/sdk64/steamclient.so"
    else
        echo "WARNING: steamclient.so not found after SteamCMD update. This might cause issues."
    fi

    # Set LD_LIBRARY_PATH and STEAMSDK_PATH for the Rust server
    export LD_LIBRARY_PATH="$HOME/.steam/sdk64:$LD_LIBRARY_PATH"
    export STEAMSDK_PATH="$HOME/.steam/sdk64"
    echo "LD_LIBRARY_PATH set to: $LD_LIBRARY_PATH"
    echo "STEAMSDK_PATH set to: $STEAMSDK_PATH"

else
    echo -e "Not updating game server as auto update was set to 0. Starting Server"
fi

# Replace Startup Variables
MODIFIED_STARTUP=`eval echo $(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')`
echo ":/home/container$ ${MODIFIED_STARTUP}"

if [[ "${FRAMEWORK}" == "carbon" ]]; then
    echo "Updating Carbon..."

    if [[ "${BRANCH}" == "release" ]]; then
        curl -sSL "https://github.com/CarbonCommunity/Carbon.Core/releases/download/production_build/Carbon.Linux.Release.tar.gz" | tar zx
    else
        curl -sSL "https://github.com/CarbonCommunity/Carbon/releases/download/preview_build/Carbon.Linux.Debug.tar.gz" | tar zx
    fi

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

# Run the Server
node /wrapper.js "${MODIFIED_STARTUP}"
