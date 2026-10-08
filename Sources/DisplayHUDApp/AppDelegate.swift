import AppKit
import DisplayHUDCore
import DisplayHUDPlatform

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let betterDisplayBundleID = "pro.betterdisplay.BetterDisplay"
    private let securityTransitionBundleIDs: Set<String> = [
        "com.macosbytes.lockpro",
        "com.apple.SecurityAgent",
    ]
    private var status: RuntimeStatus!
    private var brightnessBackend: BetterDisplayBackend!
    private var audioBackend: CoreAudioVolumeBackend!
    private var coordinator: InputCoordinator!
    private var eventTap: MediaKeyEventTap!
    private var menuController: MenuController!
    private var audioMonitor: CoreAudioDefaultOutputMonitor?
    private var brightnessRecoveryTask: Task<Void, Never>?
    private var audioRecoveryTask: Task<Void, Never>?
    private var lifecycleRecoveryTask: Task<Void, Never>?
    private var tapPriorityMonitorTask: Task<Void, Never>?
    private var securityShieldTransitionActive = false
    private let tapPriorityPolicy = TapPriorityPolicy.displayHUD
    private let backendRecovery = BoundedAvailabilityRecovery(
        retryDelays: [
            .milliseconds(250),
            .milliseconds(500),
            .seconds(1),
            .seconds(2),
            .seconds(4),
            .seconds(8),
            .seconds(16),
            .seconds(30),
            .seconds(60),
        ]
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let hasStoredEnabled = UserDefaults.standard.object(forKey: "DisplayHUDEnabled") != nil
        let enabled = hasStoredEnabled
            ? UserDefaults.standard.bool(forKey: "DisplayHUDEnabled")
            : true
        status = RuntimeStatus(enabled: enabled)

        brightnessBackend = BetterDisplayBackend(
            transport: DistributedNotificationTransport(),
            timeout: .milliseconds(250)
        )
        audioBackend = CoreAudioVolumeBackend()
        let engine = ControlEngine(
            brightnessBackend: brightnessBackend,
            volumeBackend: audioBackend
        )
        coordinator = InputCoordinator(
            engine: engine,
            audioBackend: audioBackend,
            presenter: HUDPresenter(),
            status: status,
            recoveryHandler: { [weak self] key in
                self?.recoverBackend(for: key)
            }
        )

        eventTap = MediaKeyEventTap(
            availability: { [status] key in status?.canHandle(key) ?? false },
            handler: { [weak coordinator] event in
                Task { @MainActor in await coordinator?.handle(event) }
            },
            healthHandler: { [status] health in status?.setEventTapHealth(health) },
            availabilityMissHandler: { [weak self] key in
                Task { @MainActor in
                    self?.recoverBackend(for: key)
                }
            }
        )
        menuController = MenuController(status: status) { [weak coordinator] in
            coordinator?.showTestHUD()
        }

        audioMonitor = CoreAudioDefaultOutputMonitor { [weak self] in
            Task { @MainActor in self?.startAudioRecovery() }
        }
        observeApplicationLifecycle()
        eventTap.start(promptForAccessibility: true)

        startBrightnessRecovery()
        startAudioRecovery()
        startTapPriorityMonitor()
        // Launch at Login is never enabled automatically. The user opts in
        // explicitly through the menu bar "Launch at Login" toggle.
    }

    func applicationWillTerminate(_ notification: Notification) {
        brightnessRecoveryTask?.cancel()
        audioRecoveryTask?.cancel()
        lifecycleRecoveryTask?.cancel()
        tapPriorityMonitorTask?.cancel()
        eventTap?.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    private func probeBrightness() async -> Bool {
        guard let target = ScreenTargetLocator.underPointer() else {
            status.setBrightness(available: false, detail: "No active display")
            return false
        }
        do {
            let value = try await brightnessBackend.readBrightness(for: target.display)
            status.setBrightness(
                available: true,
                detail: String(
                    format: "Connected • %.1f%%",
                    locale: Locale(identifier: "en_US_POSIX"),
                    value.percent
                )
            )
            status.setSelectedDisplay(target.name)
            return true
        } catch {
            status.setBrightness(available: false, detail: "Unavailable: \(error)")
            return false
        }
    }

    private func startBrightnessRecovery() {
        brightnessRecoveryTask?.cancel()
        brightnessRecoveryTask = Task { [weak self] in
            guard let self else { return }
            _ = await backendRecovery.run { [weak self] in
                guard let self else { return false }
                return await self.probeBrightness()
            }
        }
    }

    private func startAudioRecovery() {
        audioRecoveryTask?.cancel()
        audioRecoveryTask = Task { [weak self] in
            guard let self else { return }
            _ = await backendRecovery.run { [weak self] in
                guard let self else { return false }
                return await self.probeAudio()
            }
        }
    }

    private func probeAudio() async -> Bool {
        do {
            let state = try await audioBackend.readAudioState()
            let capabilities = try await audioBackend.capabilities()
            status.setAudio(
                volumeSettable: capabilities.volumeSettable,
                muteSettable: capabilities.muteSettable,
                detail: String(
                    format: "Device %u • volume %.1f%% • mute %@",
                    locale: Locale(identifier: "en_US_POSIX"),
                    capabilities.device,
                    state.volume.percent,
                    capabilities.muteSettable ? "supported" : "native fallback"
                )
            )
            return capabilities.volumeSettable
        } catch {
            status.setAudio(
                volumeSettable: false,
                muteSettable: false,
                detail: "Unavailable: \(error)"
            )
            return false
        }
    }

    private func recoverBackend(for key: MediaKey) {
        // If the callback is executing, the tap exists, but its cached logical
        // health may still be stale after login or a security transition.
        // Re-verify it alongside the backend that rejected this key.
        eventTap.recoverAfterLifecycleTransition()
        switch key {
        case .brightnessUp, .brightnessDown:
            startBrightnessRecovery()
        case .volumeUp, .volumeDown, .mute:
            startAudioRecovery()
        }
    }

    private func observeApplicationLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(workspaceApplicationLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(workspaceApplicationTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(workspaceApplicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(workspaceLifecycleWillSuspend(_:)),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(workspaceLifecycleDidResume(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(workspaceLifecycleWillSuspend(_:)),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(workspaceLifecycleDidResume(_:)),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(workspaceLifecycleDidResume(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(workspaceSpaceDidChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func workspaceApplicationLaunched(_ notification: Notification) {
        guard let bundleID = application(in: notification)?.bundleIdentifier else { return }
        if bundleID == betterDisplayBundleID {
            startBrightnessRecovery()
        }
    }

    @objc private func workspaceApplicationTerminated(_ notification: Notification) {
        guard application(in: notification)?.bundleIdentifier == betterDisplayBundleID else { return }
        brightnessRecoveryTask?.cancel()
        status.setBrightness(available: false, detail: "BetterDisplay is not running")
    }

    @objc private func workspaceApplicationActivated(_ notification: Notification) {
        guard let bundleID = application(in: notification)?.bundleIdentifier else { return }
        if securityTransitionBundleIDs.contains(bundleID) {
            securityShieldTransitionActive = true
            prepareForLifecycleInterruption()
            return
        }

        guard securityShieldTransitionActive else { return }
        securityShieldTransitionActive = false
        recoverFromLifecycleTransition(
            after: .milliseconds(100),
            refreshBackends: true
        )
    }

    @objc private func workspaceLifecycleWillSuspend(_ notification: Notification) {
        prepareForLifecycleInterruption()
    }

    @objc private func workspaceLifecycleDidResume(_ notification: Notification) {
        securityShieldTransitionActive = false
        recoverFromLifecycleTransition(
            after: .milliseconds(150),
            refreshBackends: true
        )
    }

    @objc private func workspaceSpaceDidChange(_ notification: Notification) {
        recoverFromLifecycleTransition(
            after: .milliseconds(50),
            refreshBackends: false
        )
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        recoverFromLifecycleTransition(
            after: .milliseconds(150),
            refreshBackends: true
        )
    }

    private func prepareForLifecycleInterruption() {
        lifecycleRecoveryTask?.cancel()
        tapPriorityMonitorTask?.cancel()
        brightnessRecoveryTask?.cancel()
        audioRecoveryTask?.cancel()
        eventTap.prepareForLifecycleTransition()
        lifecycleRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await coordinator.resetForLifecycleTransition()
        }
    }

    private func recoverFromLifecycleTransition(
        after delay: Duration,
        refreshBackends: Bool
    ) {
        lifecycleRecoveryTask?.cancel()
        eventTap.prepareForLifecycleTransition()
        lifecycleRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await coordinator.resetForLifecycleTransition()
            do {
                try await Task.sleep(for: delay)
                try Task.checkCancellation()
            } catch {
                return
            }
            eventTap.recoverAfterLifecycleTransition()
            startTapPriorityMonitor()
            if refreshBackends {
                startBrightnessRecovery()
                startAudioRecovery()
            }
            lifecycleRecoveryTask = nil
        }
    }

    private func startTapPriorityMonitor() {
        tapPriorityMonitorTask?.cancel()
        let interval = tapPriorityPolicy.monitorInterval
        tapPriorityMonitorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                    try Task.checkCancellation()
                } catch {
                    return
                }

                if !eventTap.isActuallyEnabled() {
                    eventTap.recoverAfterLifecycleTransition()
                    continue
                }
                guard eventTap.hasHeadPriority() == false else { continue }

                await coordinator.resetForLifecycleTransition()
                _ = eventTap.recreateAtHead()
            }
        }
    }

    private func application(in notification: Notification) -> NSRunningApplication? {
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }
}
