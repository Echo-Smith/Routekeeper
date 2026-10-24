import SwiftUI

enum DashboardScrollTarget: Hashable {
    case top
    case section(NetworkProtectionAnchor)
}

enum DashboardScrollID: Hashable {
    case top
    case section(NetworkProtectionAnchor)

    init(_ target: DashboardScrollTarget) {
        switch target {
        case .top:
            self = .top
        case .section(let anchor):
            self = .section(anchor)
        }
    }
}

struct DashboardScrollRequest: Equatable {
    let revision: Int
    let target: DashboardScrollTarget
}

@MainActor
final class DashboardScrollCoordinator: ObservableObject {
    static let shared = DashboardScrollCoordinator()

    @Published private(set) var request: DashboardScrollRequest?
    private var revision = 0

    func scroll(to target: DashboardScrollTarget) {
        revision += 1
        request = DashboardScrollRequest(revision: revision, target: target)
    }
}
