import SwiftUI

struct ExecApprovalPromptDialog: ViewModifier {
    @Environment(NodeAppModel.self) private var appModel: NodeAppModel

    private var isPresented: Binding<Bool> {
        Binding(
            get: { self.appModel.pendingExecApprovalPrompt != nil },
            set: { presented in
                if !presented {
                    self.appModel.dismissPendingExecApprovalPrompt()
                }
            })
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Approve command?",
            isPresented: self.isPresented,
            titleVisibility: .visible,
            presenting: self.appModel.pendingExecApprovalPrompt
        ) { prompt in
            Button("Allow once") {
                Task { await self.appModel.resolvePendingExecApprovalPrompt(decision: "allow-once") }
            }
            if prompt.allowsAllowAlways {
                Button("Always allow") {
                    Task { await self.appModel.resolvePendingExecApprovalPrompt(decision: "allow-always") }
                }
            }
            Button("Deny", role: .destructive) {
                Task { await self.appModel.resolvePendingExecApprovalPrompt(decision: "deny") }
            }
            Button("Cancel", role: .cancel) {
                self.appModel.dismissPendingExecApprovalPrompt()
            }
        } message: { prompt in
            Text(self.messageText(for: prompt))
        }
    }

    private func messageText(for prompt: NodeAppModel.ExecApprovalPrompt) -> String {
        var lines: [String] = []
        if let host = prompt.host, !host.isEmpty {
            lines.append("Host: \(host)")
        }
        lines.append(prompt.commandText)
        if let errorText = self.appModel.pendingExecApprovalPromptErrorText, !errorText.isEmpty {
            lines.append("")
            lines.append(errorText)
        }
        return lines.joined(separator: "\n")
    }
}

extension View {
    func execApprovalPromptDialog() -> some View {
        self.modifier(ExecApprovalPromptDialog())
    }
}
