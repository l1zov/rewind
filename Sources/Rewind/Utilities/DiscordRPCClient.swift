import Darwin
import Foundation

enum DiscordActivityState: Equatable {
  case idle
  case recording

  var details: String {
    switch self {
    case .idle:
      return "Idling..."
    case .recording:
      return "Capturing a game"
    }
  }
}

actor DiscordRPCClient {
  private enum DiscordOpcode: Int32 {
    case handshake = 0
    case frame = 1
  }

  private enum Constants {
    static let protocolVersion = 1
    static let connectTimeoutMilliseconds: Int32 = 1_500
    static let rewindWebsiteURL = "https://github.com/lzov/rewind"
  }

  private let clientID: String?
  private var enabled = true
  private var fileHandle: FileHandle?
  private var handshakeCompleted = false
  private var lastPublishedState: DiscordActivityState?

  init(clientID: String? = "1470439515649736865") {
    self.clientID = clientID
  }

  func setEnabled(_ isEnabled: Bool) async {
    enabled = isEnabled
    if isEnabled {
      return
    }

    await clearActivity()
    disconnect()
    lastPublishedState = nil
  }

  @discardableResult
  func publish(state: DiscordActivityState) async -> Bool {
    guard enabled else { return false }
    guard await ensureConnected() else { return false }
    guard state != lastPublishedState else { return true }

    let nonce = UUID().uuidString
    let payload: [String: Any] = [
      "cmd": "SET_ACTIVITY",
      "nonce": nonce,
      "args": [
        "pid": Int(getpid()),
        "activity": [
          "details": state.details,
          "buttons": [
            [
              "label": "Get Rewind",
              "url": Constants.rewindWebsiteURL
            ]
          ]
        ]
      ]
    ]

    do {
      try send(opcode: .frame, payload: payload)
      lastPublishedState = state
      return true
    } catch {
      AppLog.error(.app, "DRPC publish error:", error)
      disconnect()
      return false
    }
  }

  private func clearActivity() async {
    guard await ensureConnected() else { return }
    let payload: [String: Any] = [
      "cmd": "SET_ACTIVITY",
      "nonce": UUID().uuidString,
      "args": [
        "pid": Int(getpid()),
        "activity": NSNull()
      ]
    ]

    do {
      try send(opcode: .frame, payload: payload)
    } catch {
      AppLog.debug(.app, "DRPC clear error:", error)
    }
  }

  private func ensureConnected() async -> Bool {
    guard clientID != nil else {
      AppLog.debug(.app, "DRPC client id not found")
      return false
    }

    if fileHandle != nil, handshakeCompleted {
      return true
    }

    disconnect()
    for path in ipcSocketPaths() {
      guard FileManager.default.fileExists(atPath: path) else { continue }
      do {
        let handle = try connect(to: path)
        fileHandle = handle
        try sendHandshake()
        try waitForReadyDispatch()
        handshakeCompleted = true
        AppLog.info(.app, "DRPC connected:", path)
        return true
      } catch {
        disconnect()
      }
    }

    return false
  }

  private func ipcSocketPaths() -> [String] {
    var basePaths: [String] = []

    if let tempDir = ProcessInfo.processInfo.environment["TMPDIR"], !tempDir.isEmpty {
      basePaths.append(tempDir)
    }

    let nsTempDirectory = NSTemporaryDirectory()
    if !nsTempDirectory.isEmpty {
      basePaths.append(nsTempDirectory)
    }

    basePaths.append(FileManager.default.temporaryDirectory.path)
    basePaths.append("/tmp")

    var paths: [String] = []
    var seen = Set<String>()
    for basePath in basePaths {
      let normalizedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
      for socketIndex in 0..<10 {
        let path = "\(normalizedBase)/discord-ipc-\(socketIndex)"
        if seen.insert(path).inserted {
          paths.append(path)
        }
      }
    }
    return paths
  }

  private func sendHandshake() throws {
    guard let clientID else { return }
    try send(opcode: .handshake, payload: [
      "v": Constants.protocolVersion,
      "client_id": clientID
    ])
  }

  private func send(opcode: DiscordOpcode, payload: [String: Any]) throws {
    guard let fileHandle else { throw DiscordError.notConnected }
    let body = try JSONSerialization.data(withJSONObject: payload)

    var rawOpcode = opcode.rawValue.littleEndian
    var rawLength = Int32(body.count).littleEndian
    var frame = Data(bytes: &rawOpcode, count: MemoryLayout.size(ofValue: rawOpcode))
    frame.append(Data(bytes: &rawLength, count: MemoryLayout.size(ofValue: rawLength)))
    frame.append(body)
    try fileHandle.write(contentsOf: frame)
  }

  private func waitForReadyDispatch() throws {
    guard let fileHandle else { throw DiscordError.notConnected }
    var descriptorState = pollfd(fd: Int32(fileHandle.fileDescriptor), events: Int16(POLLIN), revents: 0)
    let pollResult = Darwin.poll(&descriptorState, 1, Constants.connectTimeoutMilliseconds)

    if pollResult == 0 {
      throw DiscordError.readTimedOut
    }
    if pollResult < 0 {
      throw DiscordError.connectionFailed(errno)
    }

    let header = try readExact(byteCount: 8)
    let opcode: Int32 = header.withUnsafeBytes { bytes in
      Int32(littleEndian: bytes.load(fromByteOffset: 0, as: Int32.self))
    }
    guard DiscordOpcode(rawValue: opcode) == .frame else {
      throw DiscordError.invalidFrame
    }

    let payloadLength: Int = header.withUnsafeBytes { bytes in
      Int(Int32(littleEndian: bytes.load(fromByteOffset: 4, as: Int32.self)))
    }
    guard payloadLength > 0 else {
      throw DiscordError.invalidFrame
    }

    let payloadData = try readExact(byteCount: payloadLength)
    let payloadObject = try JSONSerialization.jsonObject(with: payloadData)
    guard let frame = payloadObject as? [String: Any] else {
      throw DiscordError.invalidFrame
    }

    let command = frame["cmd"] as? String
    let event = frame["evt"] as? String
    guard command == "DISPATCH", event == "READY" else {
      throw DiscordError.handshakeRejected
    }
  }

  private func readExact(byteCount: Int) throws -> Data {
    guard let fileHandle else { throw DiscordError.notConnected }
    var data = Data()
    data.reserveCapacity(byteCount)

    while data.count < byteCount {
      let remaining = byteCount - data.count
      let chunk = try fileHandle.read(upToCount: remaining) ?? Data()
      if chunk.isEmpty {
        throw DiscordError.connectionClosed
      }
      data.append(chunk)
    }

    return data
  }

  private func disconnect() {
    if let fileHandle {
      try? fileHandle.close()
    }
    fileHandle = nil
    handshakeCompleted = false
  }

  private func connect(to path: String) throws -> FileHandle {
    let socketDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard socketDescriptor >= 0 else {
      throw DiscordError.socketCreationFailed(errno)
    }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)

    let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
    let utf8Path = Array(path.utf8)
    guard utf8Path.count < maxPathLength else {
      Darwin.close(socketDescriptor)
      throw DiscordError.pathTooLong
    }

    withUnsafeMutablePointer(to: &address.sun_path) { pathPtr in
      pathPtr.withMemoryRebound(to: CChar.self, capacity: maxPathLength) { cPath in
        cPath.initialize(repeating: 0, count: maxPathLength)
        for (index, byte) in utf8Path.enumerated() {
          cPath[index] = CChar(bitPattern: byte)
        }
      }
    }

    let addressLength = socklen_t(MemoryLayout<sa_family_t>.size + utf8Path.count + 1)
    let result = withUnsafePointer(to: &address) { addressPtr in
      addressPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
        Darwin.connect(socketDescriptor, sockaddrPtr, addressLength)
      }
    }

    guard result == 0 else {
      let code = errno
      Darwin.close(socketDescriptor)
      throw DiscordError.connectionFailed(code)
    }

    return FileHandle(fileDescriptor: socketDescriptor, closeOnDealloc: true)
  }

}

private enum DiscordError: Error {
  case notConnected
  case socketCreationFailed(Int32)
  case connectionFailed(Int32)
  case pathTooLong
  case invalidFrame
  case handshakeRejected
  case readTimedOut
  case connectionClosed
}
