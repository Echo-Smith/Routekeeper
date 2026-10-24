import Foundation
import GuardCore
import Observation

@MainActor @Observable
final class AppUpdateChecker {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, packageURL: URL)
        case failed
    }

    private(set) var state: State = .idle
    let currentVersion: String
    @ObservationIgnored private let endpoint: URL
    @ObservationIgnored private let session: URLSession

    init(
        currentVersion: String = AppUpdateChecker.installedVersion,
        endpoint: URL = URL(string: "https://api.github.com/repos/Echo-Smith/Routekeeper/releases/latest")!,
        session: URLSession = .shared
    ) {
        self.currentVersion = currentVersion
        self.endpoint = endpoint
        self.session = session
    }

    func check() async {
        guard state != .checking else { return }
        state = .checking

        do {
            var request = URLRequest(
                url: endpoint,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 15
            )
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue("Routekeeper/\(currentVersion)", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else {
                throw AppUpdateCheckError.invalidResponse
            }

            switch try AppUpdateCheck.evaluate(
                releaseData: data,
                currentVersion: currentVersion
            ) {
            case .upToDate:
                state = .upToDate
            case let .available(_, latestVersion, packageURL, _):
                state = .available(version: latestVersion, packageURL: packageURL)
            }
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed
        }
    }

    nonisolated private static var installedVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "0.0.0"
    }
}
