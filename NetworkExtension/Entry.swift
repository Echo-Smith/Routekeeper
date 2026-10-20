import Foundation
import NetworkExtension

@main
enum FilterEntry {
    static func main() {
        NEProvider.startSystemExtensionMode()
        dispatchMain()
    }
}
