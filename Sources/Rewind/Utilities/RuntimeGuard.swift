import Darwin

/// Optional anti-tamper hardening.
///
/// Disabled by default: it interferes with debuggers and some crash-reporting
/// tools, and on an open-source app it only slows *casual* dynamic analysis
/// (anyone can read the source instead, and the check is trivially patched out).
/// Treat it as a speed bump, not a lock.
///
/// To enable, add `-D REWIND_ANTIDEBUG` to the target's `swiftSettings` in
/// Package.swift, then verify the app still launches and that Sparkle updates
/// work before shipping.
enum RuntimeGuard {
	static func installAntiDebug() {
		#if REWIND_ANTIDEBUG
		// ptrace() isn't exported through Swift's Darwin overlay, so resolve it
		// from the shared C runtime at launch and issue PT_DENY_ATTACH (31),
		// which refuses any debugger attach for this process.
		typealias PtraceFn = @convention(c) (Int32, Int32, UnsafeMutableRawPointer?, Int32) -> Int32
		guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "ptrace") else { return }
		let ptrace = unsafeBitCast(symbol, to: PtraceFn.self)
		_ = ptrace(31, 0, nil, 0)
		#endif
	}
}
