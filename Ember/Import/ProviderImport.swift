import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum ProviderImport {
    static let acceptedTypes: [UTType] = [.fileURL, .folder] + UTType.importable + [.deltaSkin, .manicSkin]

    /// Copies each provided file to a temporary place Ember owns (the
    /// provider's copy goes away when its callback returns). Providers
    /// with nothing Ember can import are skipped.
    static func files(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await file(from: provider) { urls.append(url) }
        }
        return urls
    }

    private static func file(from provider: NSItemProvider) async -> URL? {
        let wanted = UTType.importable + [.deltaSkin, .manicSkin]
        guard let type = provider.registeredContentTypes.first(where: { registered in
            wanted.contains { registered.conforms(to: $0) }
        }) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                guard let url else { return continuation.resume(returning: nil) }
                let folder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Pasted-\(UUID().uuidString)", isDirectory: true)
                let target = folder.appendingPathComponent(url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: target)
                    continuation.resume(returning: target)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

extension UTType {
    static let rar = UTType(importedAs: "com.rarlab.rar-archive")
    static let sevenZip = UTType(importedAs: "org.7-zip.7-zip-archive")
    static let deltaSkin = UTType(importedAs: "com.rileytestut.delta.skin")
    static let manicSkin = UTType(importedAs: "com.alexandrethadeu.ember.manicskin")

    /// Windows .exe: self-extracting archives (installers that carry the game).
    static let windowsProgram = UTType(filenameExtension: "exe") ?? .data
    /// What the game importer takes.
    static let importable: [UTType] = [.zip, .rar, .sevenZip, .windowsProgram, .folder]
    /// What the skin importer takes.
    static let skins: [UTType] = [.deltaSkin, .manicSkin, .zip, .folder]
}
