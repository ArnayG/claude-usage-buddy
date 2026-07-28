import Foundation
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns false if the toggle did not take (most often because the app is
    /// running from a build directory rather than /Applications).
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("ClaudeUsageBuddy: login item toggle failed — \(error.localizedDescription)")
            return false
        }
    }
}
