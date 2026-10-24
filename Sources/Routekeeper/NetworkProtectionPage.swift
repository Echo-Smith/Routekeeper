import GuardCore
import SwiftUI

enum NetworkProtectionAnchor: Hashable {
    case status
    case protectionMode
    case evidence
}

struct NetworkProtectionPage: View {
    @Bindable var store: GuardStore
    let onOpenSection: (NetworkProtectionAnchor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            InspectionPage(
                store: store,
                audit: store.egressAudit,
                onOpenNetworkSettings: {
                    onOpenSection(.protectionMode)
                },
                contentMode: .statusOnly
            )
            .id(NetworkProtectionAnchor.status)

            NetworkSettingsPage(store: store)
                .frame(maxWidth: .infinity, alignment: .leading)

            InspectionPage(
                store: store,
                audit: store.egressAudit,
                onOpenNetworkSettings: {
                    onOpenSection(.protectionMode)
                },
                contentMode: .resultsOnly,
                showsToolbar: false
            )
            .id(NetworkProtectionAnchor.evidence)
        }
        .frame(maxWidth: 1040, alignment: .leading)
        .task(id: store.settings.proxyClient) {
            store.networkFilter.refresh()
        }
    }
}
