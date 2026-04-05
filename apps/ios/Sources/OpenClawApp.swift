import SwiftUI
import Foundation
import OpenClawKit
import os
import UIKit
import BackgroundTasks
@preconcurrency import UserNotifications

private struct PendingWatchPromptAction {
    var promptId: String?
    var actionId: String
    var actionLabel: String?
    var sessionKey: String?
}

private struct NotificationUserInfoSnapshot: @unchecked Sendable {
    let values: [AnyHashable: Any]
}

private typealias PendingExecApprovalPrompt = NodeAppModel.ExecApprovalPrompt

@MainActor
final class OpenClawAppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    private let logger = Logger(subsystem: "ai.openclaw.ios", category: "Push")
    private let backgroundWakeLogger = Logger(subsystem: "ai.openclaw.ios", category: "BackgroundWake")
    private static let wakeRefreshTaskIdentifier = "ai.openclaw.ios.bgrefresh"
    private var backgroundWakeTask: Task<Bool, Never>?
    private var pendingAPNsDeviceToken: Data?
    private var pendingWatchPromptActions: [PendingWatchPromptAction] = []
    private var pendingExecApprovalPrompts: [PendingExecApprovalPrompt] = []

    weak var appModel: NodeAppModel? {
        didSet {
            guard let model = self.appModel else { return }
            if let token = self.pendingAPNsDeviceToken {
                self.pendingAPNsDeviceToken = nil
                Task { @MainActor in
                    model.updateAPNsDeviceToken(token)
                }
            }
            if !self.pendingWatchPromptActions.isEmpty {
                let pending = self.pendingWatchPromptActions
                self.pendingWatchPromptActions.removeAll()
                Task { @MainActor in
                    for action in pending {
                        await model.handleMirroredWatchPromptAction(
                            promptId: action.promptId,
                            actionId: action.actionId,
                            actionLabel: action.actionLabel,
                            sessionKey: action.sessionKey)
                    }
                }
            }
            if !self.pendingExecApprovalPrompts.isEmpty {
                let pending = self.pendingExecApprovalPrompts
                self.pendingExecApprovalPrompts.removeAll()
                Task { @MainActor in
                    for prompt in pending {
                        await model.presentExecApprovalNotificationPrompt(prompt)
                    }
                }
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool
    {
        self.registerBackgroundWakeRefreshTask()
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        if let appModel = self.appModel {
            Task { @MainActor in
                appModel.updateAPNsDeviceToken(deviceToken)
            }
            return
        }

        self.pendingAPNsDeviceToken = deviceToken
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        self.logger.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void)
    {
        self.logger.info("APNs remote notification received keys=\(userInfo.keys.count, privacy: .public)")
        let snapshot = NotificationUserInfoSnapshot(values: userInfo)
        Task { @MainActor in
            let notificationCenter = LiveNotificationCenter()
            if await ExecApprovalNotificationBridge.handleResolvedPushIfNeeded(
                userInfo: snapshot.values,
                notificationCenter: notificationCenter)
            {
                if let approvalId = ExecApprovalNotificationBridge.approvalID(from: snapshot.values) {
                    self.appModel?.dismissPendingExecApprovalPrompt(approvalId: approvalId)
                }
                completionHandler(.newData)
                return
            }
            guard let appModel = self.appModel else {
                self.logger.info("APNs wake skipped: appModel unavailable")
                self.scheduleBackgroundWakeRefresh(afterSeconds: 90, reason: "silent_push_no_model")
                completionHandler(.noData)
                return
            }
            let handled = await appModel.handleSilentPushWake(snapshot.values)
            self.logger.info("APNs wake handled=\(handled, privacy: .public)")
            if !handled {
                self.scheduleBackgroundWakeRefresh(afterSeconds: 90, reason: "silent_push_not_applied")
            }
            completionHandler(handled ? .newData : .noData)
        }
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .background {
            self.scheduleBackgroundWakeRefresh(afterSeconds: 120, reason: "scene_background")
        }
    }

    private func registerBackgroundWakeRefreshTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.wakeRefreshTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handleBackgroundWakeRefresh(task: refreshTask)
        }
    }

    private func scheduleBackgroundWakeRefresh(afterSeconds delay: TimeInterval, reason: String) {
        let request = BGAppRefreshTaskRequest(identifier: Self.wakeRefreshTaskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(max(60, delay))
        do {
            try BGTaskScheduler.shared.submit(request)
            let scheduledLogMessage =
                "Scheduled background wake refresh reason=\(reason) "
                + "delaySeconds=\(max(60, delay))"
            self.backgroundWakeLogger.info(
                "\(scheduledLogMessage, privacy: .public)"
            )
        } catch {
            let failedLogMessage =
                "Failed scheduling background wake refresh reason=\(reason) "
                + "error=\(error.localizedDescription)"
            self.backgroundWakeLogger.error(
                "\(failedLogMessage, privacy: .public)"
            )
        }
    }

    private func handleBackgroundWakeRefresh(task: BGAppRefreshTask) {
        self.scheduleBackgroundWakeRefresh(afterSeconds: 15 * 60, reason: "reschedule")
        self.backgroundWakeTask?.cancel()

        let wakeTask = Task { @MainActor [weak self] in
            guard let self, let appModel = self.appModel else { return false }
            return await appModel.handleBackgroundRefreshWake(trigger: "bg_app_refresh")
        }
        self.backgroundWakeTask = wakeTask
        task.expirationHandler = {
            wakeTask.cancel()
        }
        Task {
            let applied = await wakeTask.value
            task.setTaskCompleted(success: applied)
            self.backgroundWakeLogger.info(
                "Background wake refresh finished applied=\(applied, privacy: .public)")
        }
    }

    private static func isWatchPromptNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        (userInfo[WatchPromptNotificationBridge.typeKey] as? String) == WatchPromptNotificationBridge.typeValue
    }

    private static func parseWatchPromptAction(
        from response: UNNotificationResponse) -> PendingWatchPromptAction?
    {
        let userInfo = response.notification.request.content.userInfo
        guard Self.isWatchPromptNotification(userInfo) else { return nil }

        let promptId = userInfo[WatchPromptNotificationBridge.promptIDKey] as? String
        let sessionKey = userInfo[WatchPromptNotificationBridge.sessionKeyKey] as? String

        switch response.actionIdentifier {
        case WatchPromptNotificationBridge.actionPrimaryIdentifier:
            let actionId = (userInfo[WatchPromptNotificationBridge.actionPrimaryIDKey] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !actionId.isEmpty else { return nil }
            let actionLabel = userInfo[WatchPromptNotificationBridge.actionPrimaryLabelKey] as? String
            return PendingWatchPromptAction(
                promptId: promptId,
                actionId: actionId,
                actionLabel: actionLabel,
                sessionKey: sessionKey)
        case WatchPromptNotificationBridge.actionSecondaryIdentifier:
            let actionId = (userInfo[WatchPromptNotificationBridge.actionSecondaryIDKey] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !actionId.isEmpty else { return nil }
            let actionLabel = userInfo[WatchPromptNotificationBridge.actionSecondaryLabelKey] as? String
            return PendingWatchPromptAction(
                promptId: promptId,
                actionId: actionId,
                actionLabel: actionLabel,
                sessionKey: sessionKey)
        default:
            break
        }

        guard response.actionIdentifier.hasPrefix(WatchPromptNotificationBridge.actionIdentifierPrefix) else {
            return nil
        }
        let indexString = String(
            response.actionIdentifier.dropFirst(WatchPromptNotificationBridge.actionIdentifierPrefix.count))
        guard let actionIndex = Int(indexString), actionIndex >= 0 else {
            return nil
        }
        let actionIdKey = WatchPromptNotificationBridge.actionIDKey(index: actionIndex)
        let actionLabelKey = WatchPromptNotificationBridge.actionLabelKey(index: actionIndex)
        let actionId = (userInfo[actionIdKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !actionId.isEmpty else {
            return nil
        }
        let actionLabel = userInfo[actionLabelKey] as? String
        return PendingWatchPromptAction(
            promptId: promptId,
            actionId: actionId,
            actionLabel: actionLabel,
            sessionKey: sessionKey)
    }

    private static func parseExecApprovalPrompt(
        from response: UNNotificationResponse) -> PendingExecApprovalPrompt?
    {
        ExecApprovalNotificationBridge.parsePrompt(
            actionIdentifier: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo)
    }

    private func routeWatchPromptAction(_ action: PendingWatchPromptAction) async {
        guard let appModel = self.appModel else {
            self.pendingWatchPromptActions.append(action)
            return
        }
        await appModel.handleMirroredWatchPromptAction(
            promptId: action.promptId,
            actionId: action.actionId,
            actionLabel: action.actionLabel,
            sessionKey: action.sessionKey)
        _ = await appModel.handleBackgroundRefreshWake(trigger: "watch_prompt_action")
    }

    private func routeExecApprovalPrompt(_ prompt: PendingExecApprovalPrompt) {
        guard let appModel = self.appModel else {
            self.pendingExecApprovalPrompts.append(prompt)
            return
        }
        Task { @MainActor in
            await appModel.presentExecApprovalNotificationPrompt(prompt)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        let userInfo = notification.request.content.userInfo
        if Self.isWatchPromptNotification(userInfo)
            || ExecApprovalNotificationBridge.shouldPresentNotification(userInfo: userInfo)
        {
            completionHandler([.banner, .list, .sound])
            return
        }
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void)
    {
        if let action = Self.parseWatchPromptAction(from: response) {
            Task { @MainActor [weak self] in
                guard let self else {
                    completionHandler()
                    return
                }
                await self.routeWatchPromptAction(action)
                completionHandler()
            }
            return
        }
        if let prompt = Self.parseExecApprovalPrompt(from: response) {
            Task { @MainActor [weak self] in
                guard let self else {
                    completionHandler()
                    return
                }
                self.routeExecApprovalPrompt(prompt)
                completionHandler()
            }
            return
        }
        completionHandler()
    }
}

enum WatchPromptNotificationBridge {
    static let typeKey = "openclaw.type"
    static let typeValue = "watch.prompt"
    static let promptIDKey = "openclaw.watch.promptId"
    static let sessionKeyKey = "openclaw.watch.sessionKey"
    static let actionPrimaryIDKey = "openclaw.watch.action.primary.id"
    static let actionPrimaryLabelKey = "openclaw.watch.action.primary.label"
    static let actionSecondaryIDKey = "openclaw.watch.action.secondary.id"
    static let actionSecondaryLabelKey = "openclaw.watch.action.secondary.label"
    static let actionPrimaryIdentifier = "openclaw.watch.action.primary"
    static let actionSecondaryIdentifier = "openclaw.watch.action.secondary"
    static let actionIdentifierPrefix = "openclaw.watch.action."
    static let actionIDKeyPrefix = "openclaw.watch.action.id."
    static let actionLabelKeyPrefix = "openclaw.watch.action.label."
    static let categoryPrefix = "openclaw.watch.prompt.category."

    @MainActor
    static func scheduleMirroredWatchPromptNotificationIfNeeded(
        invokeID: String,
        params: OpenClawWatchNotifyParams,
        sendResult: WatchNotificationSendResult) async
    {
        guard sendResult.queuedForDelivery || !sendResult.deliveredImmediately else { return }

        let title = params.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = params.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !body.isEmpty else { return }
        guard await self.requestNotificationAuthorizationIfNeeded() else { return }

        let normalizedActions = (params.actions ?? []).compactMap { action -> OpenClawWatchAction? in
            let id = action.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = action.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !label.isEmpty else { return nil }
            return OpenClawWatchAction(id: id, label: label, style: action.style)
        }
        let displayedActions = Array(normalizedActions.prefix(4))

        let center = UNUserNotificationCenter.current()
        var categoryIdentifier = ""
        if !displayedActions.isEmpty {
            let categoryID = "\(self.categoryPrefix)\(invokeID)"
            let category = UNNotificationCategory(
                identifier: categoryID,
                actions: self.categoryActions(displayedActions),
                intentIdentifiers: [],
                options: [])
            await self.upsertNotificationCategory(category, center: center)
            categoryIdentifier = categoryID
        }

        var userInfo: [AnyHashable: Any] = [
            self.typeKey: self.typeValue,
        ]
        if let promptId = params.promptId?.trimmingCharacters(in: .whitespacesAndNewlines), !promptId.isEmpty {
            userInfo[self.promptIDKey] = promptId
        }
        if let sessionKey = params.sessionKey?.trimmingCharacters(in: .whitespacesAndNewlines), !sessionKey.isEmpty {
            userInfo[self.sessionKeyKey] = sessionKey
        }
        for (index, action) in displayedActions.enumerated() {
            userInfo[self.actionIDKey(index: index)] = action.id
            userInfo[self.actionLabelKey(index: index)] = action.label
            if index == 0 {
                userInfo[self.actionPrimaryIDKey] = action.id
                userInfo[self.actionPrimaryLabelKey] = action.label
            } else if index == 1 {
                userInfo[self.actionSecondaryIDKey] = action.id
                userInfo[self.actionSecondaryLabelKey] = action.label
            }
        }

        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "OpenClaw" : title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        if !categoryIdentifier.isEmpty {
            content.categoryIdentifier = categoryIdentifier
        }
        if #available(iOS 15.0, *) {
            switch params.priority ?? .active {
            case .passive:
                content.interruptionLevel = .passive
            case .timeSensitive:
                content.interruptionLevel = .timeSensitive
            case .active:
                content.interruptionLevel = .active
            }
        }

        let request = UNNotificationRequest(
            identifier: "watch.prompt.\(invokeID)",
            content: content,
            trigger: nil)
        try? await self.addNotificationRequest(request, center: center)
    }

    static func actionIDKey(index: Int) -> String {
        "\(self.actionIDKeyPrefix)\(index)"
    }

    static func actionLabelKey(index: Int) -> String {
        "\(self.actionLabelKeyPrefix)\(index)"
    }

    private static func categoryActions(_ actions: [OpenClawWatchAction]) -> [UNNotificationAction] {
        actions.enumerated().map { index, action in
            let identifier: String
            switch index {
            case 0:
                identifier = self.actionPrimaryIdentifier
            case 1:
                identifier = self.actionSecondaryIdentifier
            default:
                identifier = "\(self.actionIdentifierPrefix)\(index)"
            }
            return UNNotificationAction(
                identifier: identifier,
                title: action.label,
                options: self.notificationActionOptions(style: action.style))
        }
    }

    private static func notificationActionOptions(style: String?) -> UNNotificationActionOptions {
        switch style?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "destructive":
            return [.destructive]
        case "foreground":
            // For mirrored watch actions, keep handling in background when possible.
            return []
        default:
            return []
        }
    }

    private static func requestNotificationAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await self.notificationAuthorizationStatus(center: center)
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if !granted { return false }
            let updatedStatus = await self.notificationAuthorizationStatus(center: center)
            if self.isAuthorizationStatusAllowed(updatedStatus) {
                // Refresh APNs registration immediately after the first permission grant so the
                // gateway can receive a push registration without requiring an app relaunch.
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
            return self.isAuthorizationStatusAllowed(updatedStatus)
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func isAuthorizationStatusAllowed(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    private static func notificationAuthorizationStatus(
        center: UNUserNotificationCenter
    ) async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private static func upsertNotificationCategory(
        _ category: UNNotificationCategory,
        center: UNUserNotificationCenter) async
    {
        await withCheckedContinuation { continuation in
            center.getNotificationCategories { categories in
                var updated = categories
                updated.update(with: category)
                center.setNotificationCategories(updated)
                continuation.resume()
            }
        }
    }

    private static func addNotificationRequest(
        _ request: UNNotificationRequest,
        center: UNUserNotificationCenter
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                ThrowingContinuationSupport.resumeVoid(continuation, error: error)
            }
        }
    }
}

@MainActor
enum ExecApprovalNotificationBridge {
    static let typeKey = "openclaw.type"
    static let typeValue = "exec.approval"
    static let approvalIDKey = "openclaw.exec.approval.id"
    static let actionAllowOnceIdentifier = "openclaw.exec.approval.allow-once"
    static let actionAllowAlwaysIdentifier = "openclaw.exec.approval.allow-always"
    static let actionDenyIdentifier = "openclaw.exec.approval.deny"
    private static let resolvedKinds: Set<String> = [
        "exec.approval.resolved",
        "exec.approval.cleanup",
    ]

    static func approvalID(from userInfo: [AnyHashable: Any]) -> String? {
        self.normalizedText(userInfo[self.approvalIDKey])
            ?? self.normalizedText(userInfo["approvalId"])
            ?? self.normalizedText(self.openClawPayloadValue("approvalId", userInfo: userInfo))
            ?? self.normalizedText(self.openClawPayloadValue("approval_id", userInfo: userInfo))
    }

    static func shouldPresentNotification(userInfo: [AnyHashable: Any]) -> Bool {
        self.notificationType(from: userInfo) == self.typeValue && self.approvalID(from: userInfo) != nil
    }

    static func parsePrompt(
        actionIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> NodeAppModel.ExecApprovalPrompt? {
        guard self.shouldPresentNotification(userInfo: userInfo),
              let approvalId = self.approvalID(from: userInfo)
        else {
            return nil
        }

        let allowedDecisions: [String]
        switch actionIdentifier {
        case self.actionAllowOnceIdentifier:
            allowedDecisions = ["allow-once"]
        case self.actionAllowAlwaysIdentifier:
            allowedDecisions = ["allow-always"]
        case self.actionDenyIdentifier:
            allowedDecisions = ["deny"]
        default:
            return nil
        }

        // The full prompt is fetched from the gateway after the user taps the notification action.
        return NodeAppModel.ExecApprovalPrompt(
            id: approvalId,
            commandText: "Pending approval",
            allowedDecisions: allowedDecisions,
            host: nil,
            nodeId: nil,
            agentId: nil,
            expiresAtMs: nil)
    }

    static func handleResolvedPushIfNeeded(
        userInfo: [AnyHashable: Any],
        notificationCenter: any NotificationCentering
    ) async -> Bool {
        guard self.isResolvedPush(userInfo: userInfo),
              let approvalId = self.approvalID(from: userInfo)
        else {
            return false
        }

        await self.removeNotifications(forApprovalID: approvalId, notificationCenter: notificationCenter)
        return true
    }

    static func removeNotifications(
        forApprovalID approvalId: String,
        notificationCenter: any NotificationCentering
    ) async {
        let normalizedApprovalID = approvalId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedApprovalID.isEmpty else { return }
        let identifiers = await self.notificationIdentifiers(
            forApprovalID: normalizedApprovalID,
            notificationCenter: notificationCenter)
        guard !identifiers.isEmpty else { return }
        await notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        await notificationCenter.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private static func notificationIdentifiers(
        forApprovalID approvalId: String,
        notificationCenter: any NotificationCentering
    ) async -> [String] {
        let notifications = await notificationCenter.deliveredNotifications()
        return notifications.compactMap { notification in
            self.approvalID(from: notification.userInfo) == approvalId ? notification.identifier : nil
        }
    }

    private static func isResolvedPush(userInfo: [AnyHashable: Any]) -> Bool {
        guard let kind = self.normalizedText(self.openClawPayloadValue("kind", userInfo: userInfo)) else {
            return false
        }
        return self.resolvedKinds.contains(kind)
    }

    private static func notificationType(from userInfo: [AnyHashable: Any]) -> String? {
        self.normalizedText(userInfo[self.typeKey])
            ?? self.normalizedText(self.openClawPayloadValue("type", userInfo: userInfo))
    }

    private static func openClawPayloadValue(_ key: String, userInfo: [AnyHashable: Any]) -> Any? {
        if let payload = userInfo["openclaw"] as? [String: Any] {
            return payload[key]
        }
        if let payload = userInfo["openclaw"] as? [AnyHashable: Any] {
            return payload[key]
        }
        return nil
    }

    private static func normalizedText(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

extension NodeAppModel {
    func handleMirroredWatchPromptAction(
        promptId: String?,
        actionId: String,
        actionLabel: String?,
        sessionKey: String?) async
    {
        let normalizedActionID = actionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedActionID.isEmpty else { return }

        let normalizedPromptID = promptId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSessionKey = sessionKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedActionLabel = actionLabel?.trimmingCharacters(in: .whitespacesAndNewlines)

        let event = WatchQuickReplyEvent(
            replyId: UUID().uuidString,
            promptId: (normalizedPromptID?.isEmpty == false) ? normalizedPromptID! : "unknown",
            actionId: normalizedActionID,
            actionLabel: (normalizedActionLabel?.isEmpty == false) ? normalizedActionLabel : nil,
            sessionKey: (normalizedSessionKey?.isEmpty == false) ? normalizedSessionKey : nil,
            note: "source=ios.notification",
            sentAtMs: Int(Date().timeIntervalSince1970 * 1000),
            transport: "ios.notification")
        await self._bridgeConsumeMirroredWatchReply(event)
    }
}

@main
struct OpenClawApp: App {
    @State private var appModel: NodeAppModel
    @State private var gatewayController: GatewayConnectionController
    @UIApplicationDelegateAdaptor(OpenClawAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Self.installUncaughtExceptionLogger()
        GatewaySettingsStore.bootstrapPersistence()
        let appModel = NodeAppModel()
        _appModel = State(initialValue: appModel)
        _gatewayController = State(initialValue: GatewayConnectionController(appModel: appModel))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(self.appModel)
                .environment(self.appModel.voiceWake)
                .environment(self.gatewayController)
                .task {
                    self.appDelegate.appModel = self.appModel
                }
                .onOpenURL { url in
                    Task { await self.appModel.handleDeepLink(url: url) }
                }
                .onChange(of: self.scenePhase) { _, newValue in
                    self.appModel.setScenePhase(newValue)
                    self.gatewayController.setScenePhase(newValue)
                    self.appDelegate.scenePhaseChanged(newValue)
                }
        }
    }
}

extension OpenClawApp {
    private static func installUncaughtExceptionLogger() {
        NSLog("OpenClaw: installing uncaught exception handler")
        NSSetUncaughtExceptionHandler { exception in
            // Useful when the app hits NSExceptions from SwiftUI/WebKit internals; these do not
            // produce a normal Swift error backtrace.
            let reason = exception.reason ?? "(no reason)"
            NSLog("UNCAUGHT EXCEPTION: %@ %@", exception.name.rawValue, reason)
            for line in exception.callStackSymbols {
                NSLog("  %@", line)
            }
        }
    }
}
