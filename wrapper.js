#!/usr/bin/env node

const fs = require("fs");
const { spawn } = require("child_process"); // <-- Wichtig: spawn importieren

// Leere die Logdatei beim Start
fs.writeFile("latest.log", "", (err) => {
    if (err) console.log("Callback error in appendFile:" + err);
});

// Die Argumente, die an den Node.js-Skript übergeben wurden
// process.argv[0] ist 'node', process.argv[1] ist '/wrapper.js'
// process.argv[2] wäre das erste Argument für RustDedicated, z.B. './RustDedicated'
// process.argv.slice(2) gibt uns genau die Argumente für das Child-Programm
const argsForRust = process.argv.slice(2);

if (argsForRust.length < 1) {
    console.log("Error: No startup command or arguments provided.");
    process.exit(1); // Exit with error code
}

// Den Befehl und die Argumente trennen
const commandToExecute = argsForRust[0]; // Sollte './RustDedicated' sein
const actualArgsForCommand = argsForRust.slice(1); // Alle Parameter NACH './RustDedicated'

console.log("Starting Rust...");
console.log(`Executing: ${commandToExecute} ${actualArgsForCommand.join(' ')}`); // Für Debugging

const seenPercentage = {};

function filter(data) {
    const str = data.toString();
    if (str.startsWith("Loading Prefab Bundle ")) { // Rust seems to spam the same percentage, so filter out any duplicates.
        const percentage = str.substr("Loading Prefab Bundle ".length);
        if (seenPercentage[percentage]) return;

        seenPercentage[percentage] = true;
    }

    console.log(str);
}

var exited = false;
// WICHTIG: spawn() anstelle von exec() verwenden
const gameProcess = spawn(commandToExecute, actualArgsForCommand, {
    stdio: 'inherit', // Standardausgabe des Child-Prozesses direkt in die des Wrappers leiten
    cwd: '/home/container' // Sicherstellen, dass das Programm im richtigen Verzeichnis gestartet wird
});

gameProcess.on('error', (err) => {
    console.error('Failed to start RustDedicated process:', err);
    process.exit(1);
});

gameProcess.on('close', function (code, signal) {
    exited = true;
    if (code !== null) { // code can be null if process was killed by signal
        console.log(`Main game process exited with code ${code}`);
    } else if (signal) {
        console.log(`Main game process exited due to signal ${signal}`);
    }
    process.exit(code || 0); // Exit with game's exit code, or 0 if by signal
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

var waiting = true;
var poll = function () {
    function createPacket(command) {
        var packet = {
            Identifier: -1,
            Message: command,
            Name: "WebRcon"
        };
        return JSON.stringify(packet);
    }

    var serverHostname = process.env.RCON_IP ? process.env.RCON_IP : "localhost";
    var serverPort = process.env.RCON_PORT;
    var serverPassword = process.env.RCON_PASS;
    var WebSocket = require("ws");

    // Sicherstellen, dass WebSocket nur einmal importiert wird, um Fehler zu vermeiden
    if (typeof WebSocket === 'undefined') {
         // Dies sollte nicht passieren, wenn 'ws' im Dockerfile installiert ist.
         // Kann aber bei lokalen Tests ohne 'npm install ws' auftreten.
        console.error("WebSocket module not found. Please ensure 'ws' is installed in your Docker image.");
        setTimeout(poll, 5000); // Erneuter Versuch
        return;
    }


    var ws = new WebSocket("ws://" + serverHostname + ":" + serverPort + "/" + serverPassword);

    ws.on("open", function open() {
        console.log("Connected to RCON. Generating the map now. Please wait until the server status switches to \"Running\".");
        waiting = false;

        // Hack to fix broken console output
        ws.send(createPacket('status'));

        process.stdin.removeListener('data', initialListener);
        // Da wir stdio: 'inherit' verwenden, leitet spawn die Ausgabe direkt weiter.
        // Diese Listener sind möglicherweise nicht mehr nötig oder würden die Ausgabe duplizieren.
        //gameProcess.stdout.removeListener('data', filter);
        //gameProcess.stderr.removeListener('data', filter);
        process.stdin.on('data', function (text) {
            ws.send(createPacket(text));
        });
    });

    ws.on("message", function (data, flags) {
        try {
            var json = JSON.parse(data);
            if (json !== undefined) {
                if (json.Message !== undefined && json.Message.length > 0) {
                    console.log(json.Message);
                    const fs = require("fs"); // fs sollte schon oben importiert sein, aber ok hier.
                    fs.appendFile("latest.log", "\n" + json.Message, (err) => {
                        if (err) console.log("Callback error in appendFile:" + err);
                    });
                }
            } else {
                console.log("Error: Invalid JSON received");
            }
        } catch (e) {
            if (e) {
                console.log(e);
            }
        }
    });

    ws.on("error", function (err) {
        waiting = true;
        console.log("Waiting for RCON to come up...");
        setTimeout(poll, 5000);
    });

    ws.on("close", function () {
        if (!waiting) {
            console.log("Connection to server closed.");
            exited = true;
            process.exit(0); // Exit normally if RCON connection closes gracefully
        }
    });
}
poll();
