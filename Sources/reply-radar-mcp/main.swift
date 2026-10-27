import Foundation

// Server MCP su stdio: un messaggio JSON-RPC per riga.
// stdout è riservato al protocollo; su stderr vanno solo errori tecnici, mai il contenuto dei messaggi.
var server = MCPServer()
while let line = readLine(strippingNewline: true) {
    guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
    if let response = server.handle(line) {
        FileHandle.standardOutput.write(Data((response + "\n").utf8))
    }
}
