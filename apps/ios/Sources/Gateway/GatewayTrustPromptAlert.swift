import SwiftUI

struct GatewayTrustPromptAlert: ViewModifier {
    @Environment(GatewayConnectionController.self) private var gatewayController: GatewayConnectionController

    private var promptBinding: Binding<GatewayConnectionController.TrustPrompt?> {
        Binding(
            get: { self.gatewayController.pendingTrustPrompt },
            set: { _ in
                // Keep pending trust state until explicit user action.
                // `alert(item:)` may set the binding to nil during dismissal, which can race with
                // the button handler and cause accept to no-op.
            })
    }

    func body(content: Content) -> some View {
        content.alert(item: self.promptBinding) { prompt in
            Alert(
                title: Text("Trust this gateway?"),
                message: Text(
                    """
                    First-time TLS connection.

                    Verify this SHA-256 fingerprint out-of-band before trusting:
                    \(prompt.fingerprintSha256)
                    """),
                primaryButton: .cancel(Text("Cancel")) {
                    self.gatewayController.declinePendingTrustPrompt()
                },
                secondaryButton: .default(Text("Trust and connect")) {
                    Task { await self.gatewayController.acceptPendingTrustPrompt() }
                })
        }
    }
}

extension View {
    func gatewayTrustPromptAlert() -> some View {
        self.modifier(GatewayTrustPromptAlert())
    }
}

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
