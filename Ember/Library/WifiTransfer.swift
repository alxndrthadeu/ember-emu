import Foundation
import Network
import UIKit

/// "Wi-Fi" on the import screen: a small web server on the local
/// network. A browser on the same Wi-Fi opens the address, picks files
/// or a whole game folder, and they arrive in the library.
///
/// The page uploads one file per request (PUT, raw body, no multipart),
/// so big games stream straight to disk. When a batch ends the page
/// asks Ember to import what arrived.
///
/// Off by default; it stops when the app leaves the screen, and keeps
/// the phone awake while on.
@MainActor
final class WifiTransfer: ObservableObject {
    static let shared = WifiTransfer()

    @Published private(set) var isOn = false
    @Published private(set) var address: String?
    /// The file arriving right now, for the card.
    @Published private(set) var receiving: String?
    @Published var lastError: String?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "ember.wifi-transfer")
    private static let preferredPort: UInt16 = 8080

    /// Uploads wait here until their batch is imported.
    nonisolated static var staging: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("WifiUploads", isDirectory: true)
    }

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { WifiTransfer.shared.stop() }
        }
    }

    func setOn(_ on: Bool) {
        on ? start() : stop()
    }

    func start() {
        guard listener == nil else { return }
        try? FileManager.default.removeItem(at: Self.staging)
        try? FileManager.default.createDirectory(at: Self.staging, withIntermediateDirectories: true)
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let port = NWEndpoint.Port(rawValue: Self.preferredPort)!
            // The usual port, or any free one if something holds it.
            let listener: NWListener
            if let preferred = try? NWListener(using: parameters, on: port) {
                listener = preferred
            } else {
                listener = try NWListener(using: parameters)
            }
            listener.newConnectionHandler = { connection in
                HTTPConnection(connection: connection).start()
            }
            listener.stateUpdateHandler = { state in
                Task { @MainActor in WifiTransfer.shared.listenerChanged(state) }
            }
            listener.start(queue: queue)
            self.listener = listener
            isOn = true
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            lastError = error.localizedDescription
            isOn = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isOn = false
        address = nil
        receiving = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue else { return }
            if let ip = Self.wifiAddress() {
                address = "\(ip):\(port)"
            } else {
                address = nil
                lastError = String(localized: "Conecte o iPhone a uma rede Wi-Fi para usar a transferência.")
            }
        case .failed(let error):
            lastError = error.localizedDescription
            stop()
        default:
            break
        }
    }

    // MARK: - Called from connections

    nonisolated static func receiving(_ name: String?) {
        Task { @MainActor in WifiTransfer.shared.receiving = name }
    }

    /// Imports every item a batch brought (archives, folders, skins).
    nonisolated static func finish(batch: String) {
        let folder = staging.appendingPathComponent(batch, isDirectory: true)
        let items = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
        Task { @MainActor in
            WifiTransfer.shared.receiving = nil
            guard !items.isEmpty else { return }
            LibraryStore.shared.importItems(items, removeSources: true)
        }
    }

    /// The phone's IPv4 address on Wi-Fi (en0).
    nonisolated static func wifiAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = pointer {
            defer { pointer = entry.pointee.ifa_next }
            let name = String(cString: entry.pointee.ifa_name)
            guard name == "en0", let addr = entry.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                           nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }
}

/// One HTTP/1.1 request and its answer, then the connection closes.
private final class HTTPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "ember.wifi-connection")
    private var header = Data()
    private var file: FileHandle?
    private var remaining = 0
    private var self_: HTTPConnection?

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        self_ = self   // alive until the answer is sent
        connection.start(queue: queue)
        readHeader()
    }

    // MARK: Reading

    private func readHeader() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] data, _, done, error in
            if let data { header.append(data) }
            if let end = header.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: header[..<end.lowerBound], as: UTF8.self)
                let rest = header[end.upperBound...]
                handle(head: head, body: Data(rest))
            } else if error != nil || done || header.count > 32 * 1024 {
                close()
            } else {
                readHeader()
            }
        }
    }

    private func handle(head: String, body: Data) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return respond(400, "bad request") }
        let method = String(parts[0])
        guard let components = URLComponents(string: String(parts[1])) else { return respond(400, "bad request") }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value }
        var length = 0
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2, pair[0].lowercased() == "content-length" {
                length = Int(pair[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }

        switch (method, components.path) {
        case ("GET", "/"):
            respond(200, WifiPage.html, type: "text/html; charset=utf-8")
        case ("PUT", "/upload"):
            guard let batch = query["batch"].flatMap(Self.safeName),
                  let path = query["path"].flatMap(Self.safePath) else { return respond(400, "bad path") }
            receiveFile(batch: batch, path: path, length: length, first: body)
        case ("POST", "/finish"):
            guard let batch = query["batch"].flatMap(Self.safeName) else { return respond(400, "bad batch") }
            WifiTransfer.finish(batch: batch)
            respond(200, "ok")
        default:
            respond(404, "not found")
        }
    }

    private func receiveFile(batch: String, path: [String], length: Int, first: Data) {
        let fm = FileManager.default
        var target = WifiTransfer.staging.appendingPathComponent(batch, isDirectory: true)
        for component in path { target.appendPathComponent(component) }
        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: target.path, contents: nil)
            file = try FileHandle(forWritingTo: target)
        } catch {
            return respond(500, "cannot write")
        }
        WifiTransfer.receiving(path.last)
        remaining = length
        write(first)
    }

    private func write(_ data: Data) {
        let chunk = data.prefix(remaining)
        if !chunk.isEmpty {
            do { try file?.write(contentsOf: chunk) } catch { return respond(500, "disk full?") }
            remaining -= chunk.count
        }
        guard remaining > 0 else {
            try? file?.close()
            file = nil
            return respond(200, "ok")
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [self] data, _, done, error in
            if let data, !data.isEmpty {
                write(data)
            } else if error != nil || done {
                try? file?.close()
                close()
            } else {
                write(Data())
            }
        }
    }

    // MARK: Answering

    private func respond(_ status: Int, _ body: String, type: String = "text/plain; charset=utf-8") {
        let reason = [200: "OK", 400: "Bad Request", 404: "Not Found", 500: "Internal Server Error"][status] ?? "OK"
        let payload = Data(body.utf8)
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(payload.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + payload, completion: .contentProcessed { [self] _ in close() })
    }

    private func close() {
        try? file?.close()
        connection.cancel()
        self_ = nil
    }

    // MARK: Paths

    /// Batch ids from the page: letters, digits and dashes only.
    private static func safeName(_ text: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        return !text.isEmpty && text.count < 64 && text.unicodeScalars.allSatisfy(allowed.contains) ? text : nil
    }

    /// A relative path from the browser (a folder upload keeps its
    /// tree), with nothing that climbs out of the batch folder.
    private static func safePath(_ text: String) -> [String]? {
        let parts = text.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/").map(String.init)
            .filter { !$0.isEmpty && $0 != "." }
        guard !parts.isEmpty, !parts.contains(".."), parts.count < 32 else { return nil }
        return parts
    }
}

/// The upload page the browser gets, in the app's palette.
private enum WifiPage {
    static var html: String {
        let t = [
            "title": String(localized: "Enviar para o Ember"),
            "lead": String(localized: "Arraste arquivos ou a pasta de um jogo para cá. Vale .zip, .rar, .7z, .exe autoextraível, RTP, skins e saves."),
            "files": String(localized: "Escolher arquivos"),
            "folder": String(localized: "Escolher pasta"),
            "drop": String(localized: "Solte aqui"),
            "sending": String(localized: "Enviando"),
            "done": String(localized: "Pronto. Abra a Biblioteca do Ember."),
            "failed": String(localized: "O envio parou. Confira se o Wi-Fi do Ember continua ligado e tente de novo."),
        ]
        func js(_ key: String) -> String {
            (t[key] ?? "").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        }
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Ember</title><style>
        :root{--bg:#F4E9D8;--surface:#FBF5EA;--line:#EADBC3;--text:#2B211C;--muted:#6E5B4E;--accent:#C83A1E;--amber:#F7B538;--moss:#2E8C83}
        @media(prefers-color-scheme:dark){:root{--bg:#1E1814;--surface:#2A221D;--line:#3A2F28;--text:#F4E9D8;--muted:#B9A794;--accent:#EE6A2A;--moss:#4DB3A8}}
        *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:16px ui-rounded,-apple-system,system-ui,sans-serif}
        main{max-width:620px;margin:0 auto;padding:48px 20px}h1{font-size:28px;margin:0 0 8px}p{color:var(--muted);line-height:1.45;margin:0 0 24px}
        #drop{border:2px dashed var(--line);border-radius:24px;background:var(--surface);padding:40px 20px;text-align:center}
        #drop.over{border-color:var(--accent)}.row{display:flex;gap:12px;justify-content:center;flex-wrap:wrap}
        label{background:var(--accent);color:#fff;border-radius:999px;padding:12px 20px;font-weight:600;cursor:pointer}
        label.alt{background:transparent;color:var(--accent);border:2px solid var(--accent)}input{display:none}
        .hint{margin-top:16px;color:var(--muted);font-size:14px}ul{list-style:none;padding:0;margin:24px 0 0}
        li{background:var(--surface);border-radius:16px;padding:12px 16px;margin-bottom:8px;font-size:14px}
        .bar{height:6px;border-radius:3px;background:var(--line);margin-top:8px;overflow:hidden}.bar i{display:block;height:100%;width:0;background:var(--amber)}
        .ok .bar i{background:var(--moss)}#status{margin-top:16px;font-weight:600}
        </style></head><body><main>
        <h1>🔥 \(t["title"] ?? "")</h1><p>\(t["lead"] ?? "")</p>
        <div id="drop"><div class="row">
        <label>\(t["files"] ?? "")<input id="f" type="file" multiple></label>
        <label class="alt">\(t["folder"] ?? "")<input id="d" type="file" webkitdirectory multiple></label>
        </div><div class="hint">\(t["drop"] ?? "")</div></div>
        <div id="status"></div><ul id="list"></ul></main><script>
        const T={sending:'\(js("sending"))',done:'\(js("done"))',failed:'\(js("failed"))'};
        const list=document.getElementById('list'),status=document.getElementById('status'),drop=document.getElementById('drop');
        function put(batch,path,file,bar){return new Promise((ok,no)=>{const x=new XMLHttpRequest();
          x.open('PUT','/upload?batch='+batch+'&path='+encodeURIComponent(path));
          x.upload.onprogress=e=>{if(e.lengthComputable)bar.style.width=(100*e.loaded/e.total)+'%'};
          x.onload=()=>x.status==200?ok():no();x.onerror=no;x.send(file)})}
        async function send(items){if(!items.length)return;const batch=Date.now().toString(36)+'-'+Math.random().toString(36).slice(2,8);
          status.textContent=T.sending+'…';try{for(const it of items){const li=document.createElement('li');
            li.innerHTML='<div></div><div class="bar"><i></i></div>';li.firstChild.textContent=it.path;list.prepend(li);
            await put(batch,it.path,it.file,li.querySelector('i'));li.classList.add('ok')}
            await fetch('/finish?batch='+batch,{method:'POST'});status.textContent=T.done}catch(e){status.textContent=T.failed}}
        function fromInput(input){send([...input.files].map(f=>({file:f,path:f.webkitRelativePath||f.name})));input.value=''}
        document.getElementById('f').onchange=e=>fromInput(e.target);document.getElementById('d').onchange=e=>fromInput(e.target);
        function walk(entry,prefix,out){return new Promise(res=>{if(entry.isFile){entry.file(f=>{out.push({file:f,path:prefix+f.name});res()},res)}
          else{const r=entry.createReader(),all=[];const next=()=>r.readEntries(async es=>{if(!es.length){for(const e of all)await walk(e,prefix+entry.name+'/',out);res()}else{all.push(...es);next()}},res);next()}})}
        drop.ondragover=e=>{e.preventDefault();drop.classList.add('over')};drop.ondragleave=()=>drop.classList.remove('over');
        drop.ondrop=async e=>{e.preventDefault();drop.classList.remove('over');const out=[];
          for(const item of [...e.dataTransfer.items]){const en=item.webkitGetAsEntry&&item.webkitGetAsEntry();if(en)await walk(en,'',out)}send(out)};
        </script></body></html>
        """
    }
}
