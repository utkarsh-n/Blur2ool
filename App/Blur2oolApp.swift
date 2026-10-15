import SwiftUI
import BlurCore

// OWNER: SKEL (frozen; ARCHITECTURE §5.9). @main: builds the AppEnvironment once and passes the launch arguments
// (`-B2Scenario <name> [-B2Blur id] [-B2Specimen id] [-B2Floor n] [-B2Param k=v]`, ARCHITECTURE §11.4). Dark only.
@main
struct Blur2oolApp: App {
    @State private var environment = AppEnvironment.make(arguments: ProcessInfo.processInfo.arguments)

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
                .preferredColorScheme(.dark)
        }
    }
}
