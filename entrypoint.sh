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
export INTERNAL_IP=`ip route get 1 | awk '{print $(NF-2);exit}'`

# Read the current branch from the environment variable. Default to 'release'.
CURRENT_BRANCH="${BRANCH:-release}"
echo "Configured Rust Branch: <span class="math-inline">\{CURRENT\_BRANCH\}"
\# Read the last installed branch from the flag file\.
LAST\_INSTALLED\_BRANCH\=""
if \[ \-f "</span>{INSTALLED_BRANCH_FILE}" ]; then
    LAST_INSTALLED_BRANCH=<span class="math-inline">\(cat "</span>{INSTALLED_BRANCH_FILE}")
    echo "Last installed Branch detected: <span class="math-inline">\{LAST\_INSTALLED\_BRANCH\}"
fi
\# \-\-\- Re\-installation Trigger Logic \-\-\-
if \[ "</span>{LAST_INSTALLED_BRANCH}" != "<span class="math-inline">\{CURRENT\_BRANCH\}" \] \|\| \[ \! \-f "</span>{STEAMCMD_PATH}" ]; then
    if [ -n "<span class="math-inline">\{LAST\_INSTALLED\_BRANCH\}" \] && \[ "</span>{LAST_INSTALLED_BRANCH}" != "<span class="math-inline">\{CURRENT\_BRANCH\}" \]; then
echo "\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!"
echo "\!\!\! Branch change detected\: '</span>{LAST_INSTALLED_BRANCH}' -> '<span class="math-inline">\{CURRENT\_BRANCH\}' \!\!\!"
echo "\!\!\! Forcing a complete re\-installation of server files\. \!\!\!"
echo "\!\!\! Deleting all files in /home/container to trigger Pterodactyl's install script\. \!\!\!"
echo "\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!\!"
rm \-rf /home/container/\*
exit 1 \# Exit with error to trigger Pterodactyl's reinstall mechanism
elif \[ \! \-f "</span>{STEAMCMD_PATH}" ]; then
        echo "SteamCMD executable not found. This indicates a fresh installation or a corrupted one."
        echo "Proceeding with SteamCMD installation/update from entrypoint."
    fi
fi

# Write the current branch to the file so we can detect future changes.
echo "<span class="math-inline">\{CURRENT\_BRANCH\}" \> "</span>{INSTALLED_BRANCH_FILE}"

# Dynamically set the SteamCMD branch flag.
BRANCH_FLAG=""
if [ "${CURRENT_BRANCH}" != "release" ]; then
    BRANCH_FLAG="-beta <span class="math-inline">\{CURRENT\_BRANCH\}"
fi
\# SteamCMD login details\.
STEAM\_USER\=</span>{STEAM_USER:-anonymous}
STEAM_PASS=<span class="math-inline">\{STEAM\_PASS\:\-""\}
STEAM\_AUTH\=</span>{STEAM_AUTH:-""}

# Auto-update logic
if [ -z "<span class="math-inline">\{AUTO\_UPDATE\}" \] \|\| \[ "</span>{AUTO_UPDATE}" == "1" ]; then
    echo "Updating Rust server files for branch '${CURRENT_BRANCH}' (AppID: <span class="math-inline">\{SRCDS\_APPID\}\)\.\.\."
\# Save current directory, go to SteamCMD, run update, then go back to original directory\.
\# This is crucial to ensure RustDedicated is found later\.
CURRENT\_DIR\=</span>(pwd)
    cd /home/container/steamcmd || { echo "ERROR: Cannot change to SteamCMD directory. Exiting."; exit 1; }

    ./steamcmd.sh +force_install_dir /home/container +login "<span class="math-inline">\{STEAM\_USER\}" "</span>{STEAM_PASS}" "<span class="math-inline">\{STEAM\_AUTH\}" \+app\_update "</span>{SRCDS_APPID}" ${BRANCH_FLAG} validate +quit

    # Check if SteamCMD update was successful
    if [ <span class="math-inline">? \-ne 0 \]; then
echo "ERROR\: SteamCMD update failed\! Check logs for details\."
cd "</span>{CURRENT_DIR}" # Ensure we return even on error
        exit 1
    fi
    echo "Rust server files updated successfully."
    cd "${CURRENT_DIR}" # Return to the original directory (/home/container)
else
    echo "Not updating game server as AUTO_UPDATE was set to 0. Starting Server."
fi

# Permissions anpassen
echo "Setting correct file permissions for /home/container (Rust game files)..."
# We only use chmod to adjust permissions for the current user (container user).
# The chown command caused "Operation not permitted" errors, so it's removed.
chmod -R u+rwX /home/container

# Prepare the startup command for the Node.js wrapper
MODIFIED_STARTUP=`eval echo $(echo ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')`

echo "Server startup command: <span class="math-inline">\{MODIFIED\_STARTUP\}"
\# Modding Frameworks \(Carbon/Oxide\) logic
if \[\[ "</span>{FRAMEWORK}" == "carbon" ]]; then
    echo "Updating Carbon..."
    curl -sSL "https://github.com/CarbonCommunity/Carbon.Core/releases/download/production_build/Carbon.Linux.Release.tar.gz" | tar zx
    echo "Done updating Carbon!"

    export DOORSTOP_ENABLED=1
    export DOORSTOP_TARGET_ASSEMBLY="<span class="math-inline">\(pwd\)/carbon/managed/Carbon\.Preloader\.dll"
MODIFIED\_STARTUP\="LD\_PRELOAD\=</span>(pwd)/libdoorstop.so ${MODIFIED_STARTUP}"

elif [[ "<span class="math-inline">OXIDE" \=\= "1"</12\> \]\] \|\| \[\[ "</span>{FRAMEWORK}" == "oxide" ]]; then
    echo "Updating uMod..."
    curl -sSL "https://github.com/OxideMod/Oxide.Rust/releases/latest/download/Oxide.Rust-linux.zip" > umod.zip
    unzip -o -q umod.zip
    rm umod.zip
    echo "Done updating uMod!"
fi

# Fix for Rust not starting
export LD_LIBRARY_PATH=<span class="math-inline">\(pwd\)/RustDedicated\_Data/Plugins/x86\_64\:</span>(pwd)

# Ensure RustDedicated is executable before trying to run it.
# It should be found in the current directory, which should now be /home/container
chmod +x ./RustDedicated || { echo "ERROR: Could not make RustDedicated executable. Exiting."; exit 1; }

echo "Running server via Node.js wrapper..."
exec node /wrapper.js "${MODIFIED_STARTUP}"
