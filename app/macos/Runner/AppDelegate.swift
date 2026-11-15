import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // The Dart side decides what the close button does (BackgroundMode): it
  // hides the window when "keep running" is on and quits the app otherwise.
  // AppKit must not quit on its own: it also counts a hidden window as the
  // last one closed, which ended the app, and the browser bridge with it,
  // when the window was only hidden.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // A click on the Dock icon brings back the window hidden in the menu bar.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      for window in sender.windows {
        window.makeKeyAndOrderFront(self)
      }
      sender.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
