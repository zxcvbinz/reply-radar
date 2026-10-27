import Foundation

/// Trova il database di WhatsApp Desktop e controlla se macOS ci lascia leggerlo.
public enum DatabaseLocator {
    public static let containerName = "group.net.whatsapp.WhatsApp.shared"
    public static let fileName = "ChatStorage.sqlite"

    public static var groupContainersURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Group Containers", directoryHint: .isDirectory)
    }

    public static var defaultPath: String {
        groupContainersURL.appending(path: "\(containerName)/\(fileName)").path
    }

    public enum Access: Equatable, Sendable {
        case readable
        /// Il file c'è ma macOS ne blocca la lettura: manca Accesso completo al disco.
        case denied
        case missing
    }

    /// Prova ad aprire davvero il file: `access()` non tiene conto dei permessi di Privacy, `open()` sì.
    public static func access(atPath path: String) -> Access {
        let fd = open(path, O_RDONLY)
        if fd >= 0 {
            close(fd)
            return .readable
        }
        return errno == ENOENT ? .missing : .denied
    }

    /// Il permesso che conta: poter leggere il database di WhatsApp.
    /// Se WhatsApp non è installato si guarda il database dei permessi di macOS, leggibile solo con Accesso completo al disco.
    public static var hasFullDiskAccess: Bool {
        if let path = locate(), access(atPath: path) == .readable { return true }
        let tcc = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/com.apple.TCC/TCC.db").path
        return access(atPath: tcc) == .readable
    }

    /// Percorso standard, poi gli altri container di WhatsApp (versioni beta o rinominate).
    public static func locate() -> String? {
        if access(atPath: defaultPath) != .missing { return defaultPath }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: groupContainersURL.path)) ?? []
        for name in names where name.localizedCaseInsensitiveContains("whatsapp") {
            let candidate = groupContainersURL.appending(path: "\(name)/\(fileName)").path
            if access(atPath: candidate) != .missing { return candidate }
        }
        return nil
    }

    /// Cartella da cui partono i percorsi degli allegati (`Media/...`).
    public static func mediaRoot(forDatabase path: String) -> URL {
        URL(fileURLWithPath: path).deletingLastPathComponent().appending(path: "Message", directoryHint: .isDirectory)
    }

    public struct FileInfo: Sendable {
        public let size: Int64
        public let modified: Date
    }

    /// Dimensione e ultima modifica, contando anche il file WAL dove finiscono i messaggi più recenti.
    public static func fileInfo(atPath path: String) -> FileInfo? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path) else { return nil }
        var modified = attrs[.modificationDate] as? Date ?? .distantPast
        if let wal = try? fm.attributesOfItem(atPath: path + "-wal"), let walDate = wal[.modificationDate] as? Date {
            modified = max(modified, walDate)
        }
        return FileInfo(size: (attrs[.size] as? NSNumber)?.int64Value ?? 0, modified: modified)
    }
}
