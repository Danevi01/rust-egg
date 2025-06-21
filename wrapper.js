#!/usr/bin/env node

const fs = require("fs");
const { spawn } = require("child_process"); // 'spawn' ist entscheidend für die korrekte Programmausführung

// Leere die Logdatei beim Start, um immer einen frischen Log zu haben.
fs.writeFile("latest.log", "", (err) => {
    if (err) console.log("Callback error in appendFile:", err);
});

// `process.argv` enthält: ['/usr/bin/node', '/wrapper.js', './RustDedicated', '-batchmode', ...]
// Wir möchten die Argumente ab dem dritten Element ('./RustDedicated') haben,
// da die ersten beiden der Node-Interpreter und der Wrapper selbst sind.
// Dank "exec node /wrapper.js "$@"" in deiner entrypoint.sh ist dieses Array jetzt korrekt befüllt!
const rustArgs = process.argv.slice(2);

// Prüfen, ob überhaupt Argumente übergeben wurden.
if (rustArgs.length < 1) {
    console.log("Error: No startup command or arguments provided to the wrapper. Please check your Pterodactyl Egg and entrypoint.sh configuration.");
    process.exit(1); // Beendet den Wrapper mit einem Fehlercode
}

// Der erste Eintrag im Argumente-Array ist der Pfad zum RustDedicated-Executable.
// Dies sollte './RustDedicated' sein.
const rustExecutablePath = rustArgs[0];

// Alle restlichen Einträge sind die tatsächlichen Argumente, die wir RustDedicated übergeben wollen.
// (z.B. '-batchmode', '-nographics', '+server.port', '28000', etc.).
const actualRustArguments = rustArgs.slice(1);

console.log("Starting Rust...");
// Debug-Ausgabe, um zu sehen, welcher Befehl und welche Argumente tatsächlich an 'spawn' übergeben werden.
// Diese Zeile sollte jetzt nur './RustDedicated' und seine Parameter zeigen.
console.log(`Executing RustDedicated with: ${rustExecutablePath} ${actualRustArguments.join(' ')}`);

// Ein kleines Filterobjekt, um wiederholte "Loading Prefab Bundle"-Meldungen zu unterdrücken.
// (Beibehalten, da dies eine nützliche Funktion des Wrappers ist, die über die Pterodactyl-Standardausgabe hinausgeht)
const seenPercentage = {};

function filter(data) {
    const str = data.toString();
    if (str.startsWith("Loading Prefab Bundle ")) {
        const percentage = str.substr("Loading Prefab Bundle ".length);
        if (seenPercentage[percentage]) return; // Wenn schon gesehen, ignorieren

        seenPercentage[percentage] = true; // Als gesehen markieren
    }
    console.log(str); // Ausgabe auf die Konsole
}

let exited = false; // Flag, um zu verfolgen, ob der Spielprozess beendet wurde.

// Startet den RustDedicated-Prozess.
// 'spawn' ist die korrekte Methode, um ein externes Programm mit separaten Argumenten zu starten.
// Es erwartet den Programmpfad und ein Array von Argumenten.
const gameProcess = spawn(rustExecutablePath, actualRustArguments, {
    stdio: 'inherit', // WICHTIG: Leitet die Standardausgabe (stdout) und Standardfehlerausgabe (stderr)
                       // des Kindprozesses (RustDedicated) direkt in die des Elternprozesses (Wrapper) weiter.
                       // Das sorgt dafür, dass du alle Logs des Rust-Servers siehst.
    cwd: '/home/container' // Wichtig: Setzt das aktuelle Arbeitsverzeichnis für RustDedicated.
                           // Das muss dort sein, wo die Rust-Serverdateien liegen.
});

// Behandelt Fehler beim Starten des RustDedicated-Prozesses (z.B. wenn './RustDedicated' nicht gefunden wird).
gameProcess.on('error', (err) => {
    console.error(`Failed to start RustDedicated process: ${err.message}`);
    console.error(err); // Gibt den vollständigen Fehler-Stack für die Fehlersuche aus
    process.exit(1); // Beendet den Wrapper mit einem Fehlercode
});

// Wird aufgerufen, wenn der RustDedicated-Prozess beendet wird.
gameProcess.on('close', function (code, signal) {
    exited = true; // Markiert, dass der Spielprozess beendet wurde.
    if (code !== null) {
        console.log(`Main game process exited with code ${code}`);
    } else if (signal) {
        console.log(`Main game process exited due to signal ${signal}`);
    }
    process.exit(code || 0); // Beendet den Wrapper mit dem Exit-Code des Spiels (oder 0 bei Signal)
});

// Initialer Listener für stdin (Eingaben in die Konsole), bevor RCON verbunden ist.
function initialListener(data) {
    const command = data.toString().trim();
    if (command === 'quit') {
        gameProcess.kill('SIGTERM'); // Versucht den Spielprozess elegant zu beenden
    } else {
        console.log('Unable to run "' + command + '" due to RCON not being connected yet.');
    }
}
process.stdin.resume(); // Aktiviert stdin, um Eingaben zu empfangen
process.stdin.setEncoding("utf8"); // Stellt sicher, dass die Eingaben als UTF-8 interpretiert werden
process.stdin.on('data', initialListener); // Registriert den initialen Listener

// Behandelt das Beenden des Wrappers (z.B. durch Pterodactyls Stopp-Befehl).
process.on('exit', function (code) {
    if (exited) return; // Wenn der Spielprozess sich schon selbst beendet hat, nichts tun

    console.log("Received request to stop the process, stopping the game...");
    gameProcess.kill('SIGTERM'); // Sendet ein Terminate-Signal an den Spielprozess
});

let waiting = true; // Flag, um den RCON-Verbindungsstatus zu verfolgen.

// Die Poll-Funktion versucht, eine Verbindung zum RCON-Server herzustellen.
const poll = function () {
    function createPacket(command) {
        // Erstellt ein RCON-Paket im JSON-Format.
        var packet = {
            Identifier: -1, // -1 ist üblich für Konsolenbefehle
            Message: command,
            Name: "WebRcon"
        };
        return JSON.stringify(packet);
    }

    // Holt RCON-Verbindungsinformationen aus den Umgebungsvariablen.
    const serverHostname = process.env.RCON_IP || "localhost";
    const serverPort = process.env.RCON_PORT;
    const serverPassword = process.env.RCON_PASS;

    // Erfordert das 'ws'-Modul für WebSocket-Verbindungen.
    // Stelle sicher, dass 'ws' in deinem Dockerfile via `npm install ws` installiert ist.
    const WebSocket = require("ws");

    // Versucht, eine WebSocket-Verbindung zum RCON-Server herzustellen.
    const ws = new WebSocket(`ws://${serverHostname}:${serverPort}/${serverPassword}`);

    // Listener, wenn die RCON-Verbindung erfolgreich geöffnet wurde.
    ws.on("open", function open() {
        console.log("Connected to RCON. Generating the map now. Please wait until the server status switches to \"Running\".");
        waiting = false; // RCON ist verbunden

        ws.send(createPacket('status')); // Sendet einen initialen 'status'-Befehl, um die Verbindung zu bestätigen und Logs zu erhalten.

        // Entfernt den initialen stdin-Listener und ersetzt ihn durch einen,
        // der Befehle direkt an RCON sendet.
        process.stdin.removeListener('data', initialListener);
        process.stdin.on('data', function (text) {
            ws.send(createPacket(text));
        });
    });

    // Listener für Nachrichten, die über RCON empfangen werden.
    ws.on("message", function (data, flags) {
        try {
            const json = JSON.parse(data); // Versucht, die Nachricht als JSON zu parsen.
            if (json && json.Message && json.Message.length > 0) {
                // console.log(json.Message); // <-- DIESE ZEILE WIRD AUSKOMMENTIERT!
                // Schreibt die Nachricht in die Logdatei.
                fs.appendFile("latest.log", "\n" + json.Message, (err) => {
                    if (err) console.log("Callback error in appendFile:", err);
                });
            }
        } catch (e) {
            console.log("Error parsing RCON message:", e.message || e);
        }
    });

    // Listener für Fehler bei der RCON-Verbindung.
    ws.on("error", function (err) {
        waiting = true; // Markiert, dass die Verbindung fehlgeschlagen ist.
        console.log("Waiting for RCON to come up... (Error: " + err.message + ")");
        setTimeout(poll, 5000); // Versucht es nach 5 Sekunden erneut.
    });

    // Listener, wenn die RCON-Verbindung geschlossen wird.
    ws.on("close", function (code, reason) {
        if (!waiting) { // Wenn die Verbindung nicht im "Warte-Modus" war, bedeutet das einen unerwarteten Abbruch.
            console.log(`Connection to server closed. Code: ${code}, Reason: ${reason}`);
            exited = true; // Markiert, dass der Prozess als beendet gilt
            process.exit(0); // Beendet den Wrapper (oft ein Zeichen, dass der Server selbst gestoppt hat)
        }
    });
};

poll(); // Startet den RCON-Polling-Prozess
