#!/usr/bin/env node

const fs = require("fs");
const { spawn } = require("child_process");

// Leere die Logdatei beim Start
fs.writeFile("latest.log", "", (err) => {
    if (err) console.log("Callback error in appendFile:" + err);
});

// `process.argv` enthält: ['/path/to/node', '/wrapper.js', './RustDedicated', '-batchmode', ...]
// Wir brauchen ab './RustDedicated'
const argsFromPterodactyl = process.argv.slice(2); // ['./RustDedicated', '-batchmode', ...]

if (argsFromPterodactyl.length < 1) {
    console.log("Error: No startup command or arguments provided to the wrapper.");
    process.exit(1);
}

// Der erste Eintrag im Array ist der Pfad zum RustDedicated-Executable
const rustExecutablePath = argsFromPterodactyl[0]; // Das sollte './RustDedicated' sein

// Alle restlichen Einträge sind die Argumente für RustDedicated
const rustArguments = argsFromPterodactyl.slice(1); // ['-batchmode', '-nographics', ...]

console.log("Starting Rust...");
console.log(`Attempting to execute: ${rustExecutablePath} ${rustArguments.join(' ')}`); // Für Debugging

const seenPercentage = {};

function filter(data) {
    const str = data.toString();
    if (str.startsWith("Loading Prefab Bundle ")) {
        const percentage = str.substr("Loading Prefab Bundle ".length);
        if (seenPercentage[percentage]) return;

        seenPercentage[percentage] = true;
    }
    console.log(str);
}

let exited = false;
// WICHTIG: spawn() mit dem direkten Executable-Pfad und den Argumenten aufrufen
const gameProcess = spawn(rustExecutablePath, rustArguments, {
    stdio: 'inherit',
    cwd: '/home/container' // Wichtig: Pfad auf das Server-Verzeichnis setzen
});

gameProcess.on('error', (err) => {
    console.error(`Failed to start RustDedicated process: ${err.message}`);
    console.error(err); // Den vollständigen Fehler-Stack ausgeben
    process.exit(1);
});

gameProcess.on('close', function (code, signal) {
    exited = true;
    if (code !== null) {
        console.log(`Main game process exited with code ${code}`);
    } else if (signal) {
        console.log(`Main game process exited due to signal ${signal}`);
    }
    process.exit(code || 0);
});

function initialListener(data) {
    const command = data.toString().trim();
    if (command === 'quit') {
        gameProcess.kill('SIGTERM');
    } else {
        console.log('Unable to run "' + command + '" due to RCON not being connected yet.');
    }
}
process.stdin.resume();
process.stdin.setEncoding("utf8");
process.stdin.on('data', initialListener);

process.on('exit', function (code) {
    if (exited) return;

    console.log("Received request to stop the process, stopping the game...");
    gameProcess.kill('SIGTERM');
});

let waiting = true;
const poll = function () {
    function createPacket(command) {
        var packet = {
            Identifier: -1,
            Message: command,
            Name: "WebRcon"
        };
        return JSON.stringify(packet);
    }

    const serverHostname = process.env.RCON_IP || "localhost";
    const serverPort = process.env.RCON_PORT;
    const serverPassword = process.env.RCON_PASS;

    // 'ws' Modul sollte im Dockerfile installiert sein.
    const WebSocket = require("ws");

    const ws = new WebSocket(`ws://${serverHostname}:${serverPort}/${serverPassword}`);

    ws.on("open", function open() {
        console.log("Connected to RCON. Generating the map now. Please wait until the server status switches to \"Running\".");
        waiting = false;

        ws.send(createPacket('status'));

        process.stdin.removeListener('data', initialListener);
        process.stdin.on('data', function (text) {
            ws.send(createPacket(text));
        });
    });

    ws.on("message", function (data, flags) {
        try {
            const json = JSON.parse(data);
            if (json && json.Message && json.Message.length > 0) {
                console.log(json.Message);
                fs.appendFile("latest.log", "\n" + json.Message, (err) => {
                    if (err) console.log("Callback error in appendFile:" + err);
                });
            }
        } catch (e) {
            console.log("Error parsing RCON message:", e.message || e);
        }
    });

    ws.on("error", function (err) {
        waiting = true;
        console.log("Waiting for RCON to come up... (Error: " + err.message + ")"); // Mehr Details
        setTimeout(poll, 5000);
    });

    ws.on("close", function (code, reason) {
        if (!waiting) {
            console.log(`Connection to server closed. Code: ${code}, Reason: ${reason}`);
            exited = true;
            process.exit(0);
        }
    });
}
poll();
