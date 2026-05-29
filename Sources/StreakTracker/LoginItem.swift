import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService` for the "Launch at login" toggle.
///
/// Only works when the binary runs from a proper `.app` bundle (built via build.sh).
/// Failures are logged, not thrown, so the menu never breaks if registration is
/// blocked (e.g. the app hasn't been approved yet in System Settings › Login Items).
final class LoginItem {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) {
        do {
            switch (enabled, SMAppService.mainApp.status) {
            case (true, let s) where s != .enabled:
                try SMAppService.mainApp.register()
            case (false, .enabled):
                try SMAppService.mainApp.unregister()
            default:
                break
            }
        } catch {
            NSLog("[StreakTracker] Launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }
}
