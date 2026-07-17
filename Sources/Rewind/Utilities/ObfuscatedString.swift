import Foundation

/// Keeps incidental string literals out of the binary's `strings`/`otool -s`
/// output by storing them XOR-masked and un-masking them at runtime.
///
/// This defeats *static* scanning only. The mask key ships inside the binary,
/// so the value is trivially recoverable by anyone running the app under a
/// debugger — never put real secrets (API keys, tokens, passwords) here.
enum ObfuscatedString {
	static func reveal(_ masked: [UInt8], key: [UInt8]) -> String {
		precondition(!key.isEmpty, "ObfuscatedString key must not be empty")
		var bytes = [UInt8]()
		bytes.reserveCapacity(masked.count)
		for index in masked.indices {
			bytes.append(masked[index] ^ key[index % key.count])
		}
		return String(decoding: bytes, as: UTF8.self)
	}
}
