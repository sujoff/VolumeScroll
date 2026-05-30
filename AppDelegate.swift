import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var currentVolume: Float = 0.5
    var globalMonitor: Any?
    var localMonitor: Any?
    var volumeSyncTimer: Timer?
    var lastScrollTime: TimeInterval = 0
    var popover: NSPopover?
    var sliderController: SliderViewController?

    var launchAtLogin: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return false
        }
        set {
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("Launch at login error: \(error)")
                }
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        currentVolume = getVolume()
        updateLabel()
        startVolumeSync()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
        }

        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    @objc func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            closePopover()
            showMenu()
        } else {
            togglePopover()
        }
    }

    // MARK: - Popover

    func togglePopover() {
        if let popover = popover, popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    func showPopover() {
        let vc = SliderViewController()
        vc.volume = currentVolume
        vc.onVolumeChange = { [weak self] vol in
            self?.currentVolume = vol
            self?.setVolume(vol)
            self?.updateLabel()
        }
        sliderController = vc

        let pop = NSPopover()
        pop.contentViewController = vc
        pop.contentSize = NSSize(width: 220, height: 72)
        pop.behavior = .transient
        pop.animates = true
        pop.appearance = NSAppearance.current

        if let button = statusItem.button {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover = pop
    }

    func closePopover() {
        popover?.close()
        popover = nil
        sliderController = nil
    }

    // MARK: - Scroll

    func handleScroll(_ event: NSEvent) {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        let mouseLocation = NSEvent.mouseLocation
        let buttonFrameInScreen = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )
        guard buttonFrameInScreen.contains(mouseLocation) else { return }

        let now = event.timestamp
        let isTrackpad = event.phase != []

        if isTrackpad {
            guard event.phase == .changed || event.phase == .began else { return }
            guard (now - lastScrollTime) > 0.15 else { return }
        } else {
            guard (now - lastScrollTime) > 0.08 else { return }
        }

        let delta = event.deltaY
        guard abs(delta) > 0.01 else { return }

        lastScrollTime = now

        let step: Float = 0.03
        if delta > 0 {
            currentVolume = min(1.0, currentVolume + step)
        } else {
            currentVolume = max(0.0, currentVolume - step)
        }

        setVolume(currentVolume)
        updateLabel()
        sliderController?.volume = currentVolume
    }

    // MARK: - Label

    func updateLabel() {
        DispatchQueue.main.async {
            let pct = Int(self.currentVolume * 100)
            if let button = self.statusItem.button {
                let symbolName: String
                switch pct {
                case 0:       symbolName = "speaker.slash.fill"
                case 1...33:  symbolName = "speaker.wave.1.fill"
                case 34...66: symbolName = "speaker.wave.2.fill"
                default:      symbolName = "speaker.wave.3.fill"
                }
                let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
                button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                    .withSymbolConfiguration(config)
                button.imagePosition = .imageLeft
                button.title = pct == 0 ? " Muted" : " \(pct)%"
            }
        }
    }

    // MARK: - Right-click menu

    func showMenu() {
        let menu = NSMenu()

        let pct = Int(currentVolume * 100)
        let headerItem = NSMenuItem(title: "Volume: \(pct)%", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        menu.addItem(.separator())

        let muteItem = NSMenuItem(
            title: currentVolume == 0 ? "Unmute" : "Mute",
            action: #selector(toggleMute),
            keyEquivalent: "m"
        )
        muteItem.target = self
        menu.addItem(muteItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(
            title: "Open at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit VolumeScroll",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func toggleMute() {
        currentVolume = currentVolume > 0 ? 0 : 0.5
        setVolume(currentVolume)
        updateLabel()
        sliderController?.volume = currentVolume
    }

    @objc func toggleLaunchAtLogin() {
        launchAtLogin = !launchAtLogin
    }

    // MARK: - Audio

    func startVolumeSync() {
        volumeSyncTimer?.invalidate()
        volumeSyncTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.syncVolumeFromSystemIfNeeded()
        }
        if let timer = volumeSyncTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func syncVolumeFromSystemIfNeeded() {
        let systemVolume = getVolume()
        guard abs(systemVolume - currentVolume) > 0.01 else { return }
        currentVolume = systemVolume
        updateLabel()
        sliderController?.volume = systemVolume
    }

    func getVolume() -> Float {
        let script = NSAppleScript(source: "output volume of (get volume settings)")!
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        return error == nil ? Float(result.int32Value) / 100.0 : 0.5
    }

    func setVolume(_ volume: Float) {
        let pct = Int(volume * 100)
        let script = NSAppleScript(source: "set volume output volume \(pct)")!
        var error: NSDictionary?
        script.executeAndReturnError(&error)
    }

    func applicationWillTerminate(_ notification: Notification) {
        volumeSyncTimer?.invalidate()
        volumeSyncTimer = nil
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }
}

// MARK: - Slider Popover

class SliderViewController: NSViewController {
    var onVolumeChange: ((Float) -> Void)?
    private var slider: NSSlider!
    private var iconView: NSImageView!
    private var percentLabel: NSTextField!

    var volume: Float = 0.5 {
        didSet {
            DispatchQueue.main.async {
                self.slider?.floatValue = self.volume * 100
                self.updateIcon()
                self.updatePercent()
            }
        }
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 72))
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true

        let material = NSVisualEffectView(frame: container.bounds)
        material.material = .menu
        material.blendingMode = .behindWindow
        material.state = .active
        material.autoresizingMask = [.width, .height]
        container.addSubview(material)

        iconView = NSImageView(frame: NSRect(x: 16, y: 24, width: 22, height: 22))
        iconView.imageScaling = .scaleProportionallyUpOrDown
        container.addSubview(iconView)

        slider = NSSlider(frame: NSRect(x: 46, y: 26, width: 128, height: 20))
        slider.minValue = 0
        slider.maxValue = 100
        slider.floatValue = volume * 100
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        container.addSubview(slider)

        percentLabel = NSTextField(frame: NSRect(x: 178, y: 25, width: 36, height: 20))
        percentLabel.isEditable = false
        percentLabel.isBezeled = false
        percentLabel.drawsBackground = false
        percentLabel.alignment = .right
        percentLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        percentLabel.textColor = .secondaryLabelColor
        container.addSubview(percentLabel)

        updateIcon()
        updatePercent()
        self.view = container
    }

    @objc func sliderChanged() {
        volume = slider.floatValue / 100
        onVolumeChange?(volume)
        updateIcon()
        updatePercent()
    }

    func updateIcon() {
        let pct = Int(volume * 100)
        let symbolName: String
        switch pct {
        case 0:       symbolName = "speaker.slash.fill"
        case 1...33:  symbolName = "speaker.wave.1.fill"
        case 34...66: symbolName = "speaker.wave.2.fill"
        default:      symbolName = "speaker.wave.3.fill"
        }
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            .applying(.init(paletteColors: [.controlAccentColor]))
        iconView?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    func updatePercent() {
        let pct = Int(volume * 100)
        percentLabel?.stringValue = "\(pct)%"
    }
}
