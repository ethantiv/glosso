import ServiceManagement

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
