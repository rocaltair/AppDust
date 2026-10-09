import AppKit
import SwiftUI

@main
enum AppDustMain {
    static func main() {
        if CLIRunner.shouldRun {
            exit(CLIRunner.run())
        }
        AppDustApp.main()
    }
}

struct AppDustApp: App {
    @StateObject private var model = AppDustModel()

    var body: some Scene {
        WindowGroup("AppDust") {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 1120, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .help) { }
            CommandMenu("清理") {
                Button("重新扫描") { Task { await model.scan() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.selectedApp == nil)
                Divider()
                Button("全选") { model.selectAll(true) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                Button("全不选") { model.selectAll(false) }
            }
        }
    }
}
