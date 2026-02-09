import Foundation

final class UncheckedSendable<T>: @unchecked Sendable {
  let value: T

  init(_ value: T) {
    self.value = value
  }
}
