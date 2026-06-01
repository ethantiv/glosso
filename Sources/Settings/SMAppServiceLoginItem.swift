import ServiceManagement

/// Real `LoginItemManaging` backed by `SMAppService.mainApp`. The main app needs
/// no helper plist or extra entitlement to register itself; registration is only
/// reliable once the app lives in /Applications.
@MainActor
struct SMAppServiceLoginItem: LoginItemManaging {
    var isEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval: return true
        default: return false
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
