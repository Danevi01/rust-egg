#!/bin/bash
cd /home/container

# Make internal Docker IP address available to processes.
export INTERNAL_IP=`ip route get 1 | awk '{print $(NF-2);exit}'`

# Ensure the .steam/sdk64 directory exists. SteamCMD often places files here,
# or we will symlink steamclient.so into it.
mkdir -p "$HOME/.steam/sdk64"

## If auto_update is not set or set to 1, update the game server.
if [ -z "${AUTO_UPDATE}" ] || [ "${AUTO_UPDATE}" == "1" ]; then
    echo "Starting SteamCMD update for Rust server..."
    # Execute SteamCMD. We use the full path because it's explicitly installed there.
    # "$HOME" (which is /home/container) is used as install directory for Rust.
    /home/container/steamcmd/steamcmd.sh +force_install_dir "$HOME" +login anonymous +app_update 258550 -beta "${BRANCH}" +quit
    echo "SteamCMD update complete."

    # --- Crucial for steamclient.so fix ---
    # After update, ensure steamclient.so is linked correctly and LD_LIBRARY_PATH is set.
    # The find command helps locate steamclient.so reliably within the installed game files.
    STEAMCLIENT_PATH=$(find "$HOME" -name "steamclient.so" -print -quit)
    if [ -n "$STEAMCLIENT_PATH" ]; then
        ln -sf "$STEAMCLIENT_PATH" "$HOME/.steam/sdk64/steamclient.so"
        echo "Linked steamclient.so from $STEAMCLIENT_PATH to $HOME/.steam/sdk64/steamclient.so"

        # Copy the correct steamclient.so to Rust's plugin directory for early access.
        # Use 'cp -L' to dereference the symlink and copy the actual file.
        # The 'cp: ... are the same file' warning is expected if SteamCMD already handled this.
        cp -L "$HOME/.steam/sdk64/steamclient.so" "$HOME/RustDedicated_Data/Plugins/x86_64/steamclient.so" || {
          echo "WARNING: Failed to copy steamclient.so using cp -L. Attempting a direct copy (might fail if symlink is broken)."
          cp "$HOME/.steam/sdk64/steamclient.so" "$HOME/RustDedicated_Data/Plugins/x86_64/steamclient.so"
        }
        echo "Attempted to copy steamclient.so to Rust's plugin directory."
    else
        echo "WARNING: steamclient.so not found after SteamCMD update. This might cause issues."
    fi

    # Set LD_LIBRARY_PATH and STEAMSDK_PATH for the Rust server process.
    # These must be set *before* the Rust server starts.
    export LD_LIBRARY_PATH="$HOME/.steam/sdk64:$LD_LIBRARY_PATH"
    export STEAMSDK_PATH="$HOME/.steam/sdk64"
    echo "LD_LIBRARY_PATH set to: $LD_LIBRARY_PATH"
    echo "STEAMSDK_PATH set to: $STEAMSDK_PATH"
    # --- End crucial fix ---

else
    echo -e "Not updating game server as auto update was set to 0. Starting Server"
fi

# Replace Startup Variables - This section remains unchanged.
MODIFIED_STARTUP=`eval echo $(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')`
echo ":/home/container$ ${MODIFIED_STARTUP}"

# Oxide/Carbon Modding Frameworks - This section remains unchanged.
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

# --- NEUER VERSUCH: RustDedicated direkt mit LD_PRELOAD starten ---
# Dies ist ein Versuch, die steamclient.so so früh wie möglich für Rust zu laden.
# Wir versuchen, das RustDedicated-Executable direkt zu identifizieren und zu starten.
echo "Attempting to launch RustDedicated with LD_PRELOAD..."

# Annahme: Der erste Teil von MODIFIED_STARTUP ist das RustDedicated-Executable
# und der Rest sind Argumente. Dies muss genau zu deinem STARTUP-Befehl passen.
RUST_EXECUTABLE=$(echo "${MODIFIED_STARTUP}" | awk '{print $1}')
RUST_ARGS=$(echo "${MODIFIED_STARTUP}" | cut -d' ' -f2-)

# Überprüfe, ob das Executable existiert und ausführbar ist
if [ -x "${RUST_EXECUTABLE}" ]; then
    echo "Executing: LD_PRELOAD=\"$HOME/.steam/sdk64/steamclient.so\" \"${RUST_EXECUTABLE}\" ${RUST_ARGS}"
    # Führe den Rust-Server direkt aus. Wenn er läuft, wird dieser Prozess den Container beenden.
    LD_PRELOAD="$HOME/.steam/sdk64/steamclient.so" "${RUST_EXECUTABLE}" ${RUST_ARGS}
    EXIT_CODE=$?
    echo "Direct LD_PRELOAD launch exited with code ${EXIT_CODE}. Falling back to node /wrapper.js..."
else
    echo "RustDedicated executable not found or not executable at ${RUST_EXECUTABLE}. Falling back to node /wrapper.js..."
fi

# Fallback: Wenn der direkte LD_PRELOAD-Start nicht funktioniert hat oder das Executable nicht gefunden wurde,
# starten wir den Server über den Node.js-Wrapper, wie zuvor.
node /wrapper.js "${MODIFIED_STARTUP}"
