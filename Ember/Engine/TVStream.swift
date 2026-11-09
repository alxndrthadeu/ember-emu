import ImageIO
import Network
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Jogar na TV": the game picture goes to any browser on the same
/// Wi-Fi (a smart TV, a computer hooked to a TV, a tablet), and the
/// iPhone keeps only the controller. Like a handheld plugged into a TV.
///
/// The engine copies each presented frame (engine patch 0003, at most
/// 30 per second, at the game's own resolution). Ember turns them into
/// JPEGs and sends them as a multipart stream (MJPEG), which every
/// browser shows in an <img> with no buffering: a frame shows as soon
/// as it arrives, so the delay stays around a tenth of a second.
@MainActor
final class TVStream: ObservableObject {
    static let shared = TVStream()

    @Published private(set) var isOn = false
    @Published private(set) var address: String?
    /// Browsers showing the game right now.
    @Published private(set) var viewers = 0 {
        didSet { GameLayout.shared.onTV = viewers > 0 }
    }
    @Published var lastError: String?

    private var listener: NWListener?
    private var streamer: FrameStreamer?
    private static let preferredPort: UInt16 = 8090

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { TVStream.shared.stop() }
        }
    }

    func setOn(_ on: Bool) {
        on ? start() : stop()
    }

    func start() {
        guard listener == nil, EngineSession.shared.state == .running else { return }
        guard let ip = WifiTransfer.wifiAddress() else {
            lastError = String(localized: "Conecte o iPhone a uma rede Wi-Fi para jogar na TV.")
            return
        }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener: NWListener
            if let port = NWEndpoint.Port(rawValue: Self.preferredPort),
               let preferred = try? NWListener(using: parameters, on: port) {
                listener = preferred
            } else {
                listener = try NWListener(using: parameters)
            }
            let streamer = FrameStreamer()
            listener.newConnectionHandler = { connection in
                TVConnection(connection: connection, streamer: streamer).start()
            }
            listener.stateUpdateHandler = { state in
                Task { @MainActor in
                    let tv = TVStream.shared
                    switch state {
                    case .ready:
                        if let port = tv.listener?.port?.rawValue { tv.address = "\(ip):\(port)" }
                    case .failed(let error):
                        tv.lastError = error.localizedDescription
                        tv.stop()
                    default:
                        break
                    }
                }
            }
            streamer.onViewersChanged = { count in
                Task { @MainActor in TVStream.shared.viewers = count }
            }
            mkxp_setFrameStreamEnabled(true)
            streamer.start()
            listener.start(queue: streamer.queue)
            self.listener = listener
            self.streamer = streamer
            isOn = true
            UIApplication.shared.isIdleTimerDisabled = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        mkxp_setFrameStreamEnabled(false)
        streamer?.stop()
        streamer = nil
        listener?.cancel()
        listener = nil
        isOn = false
        address = nil
        viewers = 0
        UIApplication.shared.isIdleTimerDisabled = false
    }
}

/// Reads frames from the engine, encodes them, and sends them to every
/// browser watching. Lives on its own queue.
private final class FrameStreamer: @unchecked Sendable {
    let queue = DispatchQueue(label: "ember.tv-stream", qos: .userInteractive)
    var onViewersChanged: (Int) -> Void = { _ in }

    private var timer: DispatchSourceTimer?
    private var viewers: [ObjectIdentifier: TVConnection] = [:]
    private var listeners: [ObjectIdentifier: TVConnection] = [:]
    private var samples = [Int16](repeating: 0, count: 8192 * 2)
    private var buffer = [UInt8](repeating: 0, count: 640 * 480 * 4)
    private var sequence: UInt32 = 0

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            for viewer in viewers.values { viewer.close() }
            for listener in listeners.values { listener.close() }
            viewers.removeAll()
            if !listeners.isEmpty { EmberAudioTapEnable(0, 0) }
            listeners.removeAll()
        }
    }

    /// Called on `queue`.
    func add(_ viewer: TVConnection) {
        viewers[ObjectIdentifier(viewer)] = viewer
        onViewersChanged(viewers.count)
    }

    /// Called on `queue`. The first listener turns the sound tap on and
    /// the iPhone's speaker off.
    func addListener(_ listener: TVConnection) {
        if listeners.isEmpty { EmberAudioTapEnable(1, 1) }
        listeners[ObjectIdentifier(listener)] = listener
    }

    /// Called on `queue`.
    func remove(_ connection: TVConnection) {
        let id = ObjectIdentifier(connection)
        if listeners.removeValue(forKey: id) != nil, listeners.isEmpty {
            EmberAudioTapEnable(0, 0)
        }
        guard viewers.removeValue(forKey: id) != nil else { return }
        onViewersChanged(viewers.count)
    }

    /// Moves the sound gathered since the last tick to every listener.
    private func pumpAudio() {
        guard !listeners.isEmpty else { return }
        var chunk = Data()
        while true {
            let frames = samples.withUnsafeMutableBufferPointer { EmberAudioTapRead($0.baseAddress, 8192) }
            if frames == 0 { break }
            samples.withUnsafeBytes { chunk.append(contentsOf: $0.prefix(frames * 4)) }
            if frames < 8192 { break }
        }
        guard !chunk.isEmpty else { return }
        for listener in listeners.values { listener.sendAudio(chunk) }
    }

    private func tick() {
        pumpAudio()
        guard !viewers.isEmpty else { return }
        var width: Int32 = 0, height: Int32 = 0
        var copied = buffer.withUnsafeMutableBytes { raw in
            mkxp_copyStreamFrame(raw.bindMemory(to: UInt8.self).baseAddress, Int32(raw.count),
                                 &width, &height, &sequence)
        }
        // A bigger game picture than the buffer: grow it and try again.
        if !copied, width > 0, height > 0, Int(width) * Int(height) * 4 > buffer.count {
            buffer = [UInt8](repeating: 0, count: Int(width) * Int(height) * 4)
            copied = buffer.withUnsafeMutableBytes { raw in
                mkxp_copyStreamFrame(raw.bindMemory(to: UInt8.self).baseAddress, Int32(raw.count),
                                     &width, &height, &sequence)
            }
        }
        guard copied, let jpeg = encode(width: Int(width), height: Int(height)) else { return }
        var part = Data("--emberframe\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\n\r\n".utf8)
        part.append(jpeg)
        part.append(Data("\r\n".utf8))
        for viewer in viewers.values { viewer.send(part) }
    }

    private func encode(width: Int, height: Int) -> Data? {
        let size = width * height * 4
        guard let provider = CGDataProvider(data: Data(buffer.prefix(size)) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent)
        else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

/// One browser request: the page, or the live picture.
private final class TVConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let streamer: FrameStreamer
    private var head = Data()
    private var sending = false
    private var closed = false
    /// Sound waiting to go out (never dropped, unlike frames, up to
    /// half a second).
    private var pendingAudio = Data()
    private var keepAlive: TVConnection?

    init(connection: NWConnection, streamer: FrameStreamer) {
        self.connection = connection
        self.streamer = streamer
    }

    func start() {
        keepAlive = self
        connection.start(queue: streamer.queue)
        readHead()
    }

    private func readHead() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [self] data, _, done, error in
            if let data { head.append(data) }
            if let end = head.range(of: Data("\r\n\r\n".utf8)) {
                let text = String(decoding: head[..<end.lowerBound], as: UTF8.self)
                route(text.split(separator: " ").dropFirst().first.map(String.init) ?? "/")
            } else if error != nil || done || head.count > 16 * 1024 {
                close()
            } else {
                readHead()
            }
        }
    }

    private func route(_ target: String) {
        let path = target.split(separator: "?").first.map(String.init) ?? "/"
        switch path {
        case "/", "/tv":
            respond("text/html; charset=utf-8", Data(TVPage.html.utf8))
        case "/audio":
            let rate = EmberAudioTapRate()
            let header = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nX-Sample-Rate: \(rate)\r\n"
                + "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8), completion: .contentProcessed { [self] error in
                if error != nil { close() } else { streamer.addListener(self) }
            })
            watchForClose()
        case "/stream":
            let header = "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=emberframe\r\n"
                + "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8), completion: .contentProcessed { [self] error in
                if error != nil { close() } else { streamer.add(self) }
            })
            // Notice the browser leaving.
            watchForClose()
        default:
            respond("text/plain", Data("not found".utf8), status: "404 Not Found")
        }
    }

    private func watchForClose() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [self] _, _, done, error in
            if done || error != nil { close() } else { watchForClose() }
        }
    }

    /// Sends a frame unless the browser is still taking the last one
    /// (a slow screen skips frames instead of falling behind).
    func send(_ part: Data) {
        guard !sending, !closed else { return }
        sending = true
        connection.send(content: part, completion: .contentProcessed { [self] error in
            sending = false
            if error != nil { close() }
        })
    }

    /// 16-bit stereo sound; queued while the last chunk is on its way.
    func sendAudio(_ chunk: Data) {
        guard !closed else { return }
        pendingAudio.append(chunk)
        let limit = Int(EmberAudioTapRate()) * 4 / 2
        if pendingAudio.count > limit { pendingAudio.removeFirst(pendingAudio.count - limit) }
        flushAudio()
    }

    private func flushAudio() {
        guard !sending, !closed, !pendingAudio.isEmpty else { return }
        sending = true
        let out = pendingAudio
        pendingAudio.removeAll(keepingCapacity: true)
        connection.send(content: out, completion: .contentProcessed { [self] error in
            sending = false
            if error != nil { close() } else { flushAudio() }
        })
    }

    private func respond(_ type: String, _ body: Data, status: String = "200 OK") {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
            + "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { [self] _ in close() })
    }

    func close() {
        guard !closed else { return }
        closed = true
        streamer.remove(self)
        connection.cancel()
        keepAlive = nil
    }
}

/// The page the TV opens: the game picture, crisp and as big as the
/// screen allows, on Ember's night background while it connects.
private enum TVPage {
    static var html: String {
        func text(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        }
        let connecting = text(String(localized: "Conectando ao iPhone…"))
        let hint = text(String(localized: "Clique ou aperte OK para tela cheia e som"))
        let paused = text(String(localized: "Abra um jogo no Ember, no iPhone"))
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1"><title>Ember</title>
        <style>
        html,body{margin:0;height:100%;background:#000;overflow:hidden}
        #game{position:fixed;inset:0;width:100%;height:100%;object-fit:contain;
          image-rendering:pixelated;image-rendering:crisp-edges;display:none}
        #wait{position:fixed;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;
          gap:18px;background:radial-gradient(circle at 50% 45%,#3A2A20 0,#1E1814 60%);
          font-family:ui-rounded,"SF Pro Rounded",system-ui,sans-serif;color:#B9A794;text-align:center}
        #wait b{color:#F4E9D8;font-size:64px}
        #msg{font-size:28px}#hint{font-size:18px;opacity:.7}
        </style></head><body>
        <div id="wait">\(flameSVG)<b>Ember</b><div id="msg">\(connecting)</div><div id="hint">\(hint)</div></div>
        <img id="game" alt="">
        <script>
        const game=document.getElementById('game'),wait=document.getElementById('wait'),msg=document.getElementById('msg');
        function connect(){game.src='/stream?'+Date.now()}
        game.onerror=()=>{game.style.display='none';wait.style.display='flex';msg.textContent='\(paused)';setTimeout(connect,1500)};
        setInterval(()=>{if(game.naturalWidth>0){game.style.display='block';wait.style.display='none'}},300);
        let ctx=null,playing=false;
        async function sound(){
          if(playing)return;playing=true;
          try{
            const res=await fetch('/audio?'+Date.now());
            const rate=parseInt(res.headers.get('X-Sample-Rate')||'44100');
            if(!ctx){const A=window.AudioContext||window.webkitAudioContext;ctx=new A({sampleRate:rate});}
            await ctx.resume();
            const reader=res.body.getReader();let next=0,rest=new Uint8Array(0);
            for(;;){
              const r=await reader.read();if(r.done)break;
              const bytes=new Uint8Array(rest.length+r.value.length);bytes.set(rest);bytes.set(r.value,rest.length);
              const frames=Math.floor(bytes.length/4);rest=bytes.slice(frames*4);if(!frames)continue;
              const view=new DataView(bytes.buffer,0,frames*4),buf=ctx.createBuffer(2,frames,rate);
              const L=buf.getChannelData(0),R=buf.getChannelData(1);
              for(let i=0;i<frames;i++){L[i]=view.getInt16(i*4,true)/32768;R[i]=view.getInt16(i*4+2,true)/32768}
              const src=ctx.createBufferSource();src.buffer=buf;src.connect(ctx.destination);
              const now=ctx.currentTime;if(next<now+0.04||next>now+0.5)next=now+0.12;
              src.start(next);next+=buf.duration;
            }
          }catch(e){}
          playing=false;if(ctx)setTimeout(sound,1500);
        }
        function go(){const d=document.documentElement;(d.requestFullscreen||d.webkitRequestFullscreen||(()=>{})).call(d);sound()}
        document.body.addEventListener('click',go);
        document.addEventListener('keydown',e=>{if(e.key==='Enter')go()});
        connect();
        </script></body></html>
        """
    }

    /// The app icon's pixel flame (scripts/make-app-icon.py), dark variant.
    static let flameSVG: String = {
        let map = ["....1....", "...111...", "...1211..", "..12211..", "..122211.",
                   ".1223221.", ".1233321.", ".1233321.", "..12321..", "...111..."]
        let colors: [Character: String] = ["1": "#EE6A2A", "2": "#F48A3A", "3": "#F7B538"]
        var rects = ""
        for (y, row) in map.enumerated() {
            for (x, ch) in row.enumerated() {
                if let fill = colors[ch] { rects += "<rect x=\"\(x)\" y=\"\(y)\" width=\"1\" height=\"1\" fill=\"\(fill)\"/>" }
            }
        }
        return "<svg width=\"108\" height=\"120\" viewBox=\"0 0 9 10\" shape-rendering=\"crispEdges\">\(rects)</svg>"
    }()
}

// MARK: - iPhone side

/// The game menu's sheet: turn the TV on, the address to open, and how
/// many screens are watching.
struct TVSheet: View {
    @ObservedObject private var tv = TVStream.shared
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "tv")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.highlight)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Jogar na TV")
                        .font(.title3.weight(.semibold))
                    Text("O jogo aparece no navegador da TV ou do computador, e o iPhone vira o controle.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("Jogar na TV", isOn: Binding(get: { tv.isOn }, set: { tv.setOn($0) }))
                    .labelsHidden()
                    .tint(Theme.active)
            }

            if tv.isOn, let address = tv.address {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Abra no navegador, na mesma rede Wi-Fi")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    HStack {
                        Text(verbatim: address)
                            .font(.title2.monospaced().weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        Button {
                            UIPasteboard.general.string = "http://\(address)"
                            copied = true
                            Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .frame(width: 22, height: 22)
                        }
                        .emberGlassButton()
                        .accessibilityLabel(copied ? String(localized: "Copiado") : String(localized: "Copiar endereço"))
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.active.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                )

                Label(tv.viewers == 0
                      ? String(localized: "Esperando uma tela abrir o endereço")
                      : (tv.viewers == 1 ? String(localized: "Jogando numa tela")
                                         : String(localized: "Jogando em \(tv.viewers) telas")),
                      systemImage: tv.viewers == 0 ? "hourglass" : "dot.radiowaves.left.and.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(tv.viewers == 0 ? Color.secondary : Theme.active)

                Text("Na TV, aperte OK (ou clique, no computador) para tela cheia e som: o som passa a sair na TV e o iPhone fica mudo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Funciona com smart TVs (LG, Samsung e outras), computadores e tablets: qualquer aparelho com navegador no mesmo Wi-Fi.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.colorScheme, .dark)
        .alert("Não deu certo", isPresented: Binding(get: { tv.lastError != nil }, set: { if !$0 { tv.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(tv.lastError ?? "")
        }
    }
}

/// On the iPhone, where the picture was: the game is on the TV.
struct PlayingOnTVLabel: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tv")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.highlight)
            Text("Jogando na TV")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(hex: 0xF4E9D8))
            Text("O iPhone virou o controle")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: 0xB9A794))
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}
