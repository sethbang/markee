import Foundation

// App extensions have no normal main(): the system entry point is
// NSExtensionMain, which runs the extension's XPC service loop.
@_silgen_name("NSExtensionMain")
func NSExtensionMain() -> Int32

exit(NSExtensionMain())
