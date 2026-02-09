import Foundation
import OSLog

enum AppLog {
  enum Category: String {
    case app
    case capture
    case writer
    case library
  }

  private static let subsystem: String = {
    Bundle.main.bundleIdentifier ?? "Rewind"
  }()

  private static let appLogger = Logger(subsystem: subsystem, category: Category.app.rawValue)
  private static let captureLogger = Logger(subsystem: subsystem, category: Category.capture.rawValue)
  private static let writerLogger = Logger(subsystem: subsystem, category: Category.writer.rawValue)
  private static let libraryLogger = Logger(subsystem: subsystem, category: Category.library.rawValue)

  private static let debugEnabled: Bool = {
    #if DEBUG
    let value = ProcessInfo.processInfo.environment["REWIND_DEBUG_LOGS"]
    return value == "1" || value?.lowercased() == "true"
    #else
    return false
    #endif
  }()

  private static let consoleMirrorEnabled: Bool = {
    #if DEBUG
    let value = ProcessInfo.processInfo.environment["REWIND_DEBUG_LOGS"]
    return value == "1" || value?.lowercased() == "true"
    #else
    return false
    #endif
  }()

  static func debug(_ category: Category, _ items: Any..., separator: String = " ") {
    guard debugEnabled else { return }
    log(category, items, separator: separator, level: .debug)
  }

  static func debug(_ category: Category, items: [Any], separator: String = " ") {
    guard debugEnabled else { return }
    log(category, items, separator: separator, level: .debug)
  }

  static func info(_ category: Category, _ items: Any..., separator: String = " ") {
    log(category, items, separator: separator, level: .info)
  }

  static func info(_ category: Category, items: [Any], separator: String = " ") {
    log(category, items, separator: separator, level: .info)
  }

  static func error(_ category: Category, _ items: Any..., separator: String = " ") {
    log(category, items, separator: separator, level: .error)
  }

  static func error(_ category: Category, items: [Any], separator: String = " ") {
    log(category, items, separator: separator, level: .error)
  }

  private static func log(_ category: Category, _ items: [Any], separator: String, level: OSLogType) {
    let message = items.map { String(describing: $0) }.joined(separator: separator)
    let logger: Logger
    switch category {
    case .app:
      logger = appLogger
    case .capture:
      logger = captureLogger
    case .writer:
      logger = writerLogger
    case .library:
      logger = libraryLogger
    }

    switch level {
    case .error:
      logger.error("\(message, privacy: .public)")
    case .info:
      logger.info("\(message, privacy: .public)")
    default:
      logger.debug("\(message, privacy: .public)")
    }

    if consoleMirrorEnabled {
      print("[\(category.rawValue)] \(message)")
    }
  }
}
