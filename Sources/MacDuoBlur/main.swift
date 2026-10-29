import AppKit
import CoreImage
import IOKit
import IOKit.hid
import QuartzCore

// MARK: - Hardware Lid Angle Sensor (HID 0x20 / 0x8A)
public final class HardwareLidAngleSensor {
    public enum Resolution {
        case hundredthsOfADegree // Report 7 (0.01°)
        case wholeDegrees        // Report 1 (1.0°)
        
        var reportID: Int {
            switch self {
            case .hundredthsOfADegree: return 7
            case .wholeDegrees: return 1
            }
        }
    }
    
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var resolution: Resolution?
    private var buffer = [UInt8](repeating: 0, count: 32)
    
    public var isAvailable: Bool { device != nil && resolution != nil }
    
    public init() {
        open()
    }
    
    deinit {
        if let manager = manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
    
    private func open() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDDeviceUsagePageKey: 0x20,
            kIOHIDDeviceUsageKey: 0x8A
        ]
        IOHIDManagerSetDeviceMatching(mgr, matching as CFDictionary)
        
        guard IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        self.manager = mgr
        
        guard let devices = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> else { return }
        for cand in devices {
            if let builtIn = (IOHIDDeviceGetProperty(cand, kIOHIDBuiltInKey as CFString) as? NSNumber)?.boolValue, !builtIn {
                continue
            }
            self.device = cand
            for res in [Resolution.hundredthsOfADegree, Resolution.wholeDegrees] {
                self.resolution = res
                if readAngle() != nil { return }
            }
        }
        self.device = nil
        self.resolution = nil
    }
    
    public func readAngle() -> Double? {
        guard let device = device, let resolution = resolution else { return nil }
        var length = CFIndex(buffer.count)
        let res = buffer.withUnsafeMutableBufferPointer { ptr -> IOReturn in
            guard let base = ptr.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(resolution.reportID), base, &length)
        }
        guard res == kIOReturnSuccess, length > 0, buffer[0] == UInt8(resolution.reportID) else { return nil }
        
        let deg: Double
        switch resolution {
        case .hundredthsOfADegree:
            guard length >= 5 else { return nil }
            let raw = UInt32(buffer[1]) | UInt32(buffer[2]) << 8 | UInt32(buffer[3]) << 16 | UInt32(buffer[4]) << 24
            deg = Double(raw) / 100.0
        case .wholeDegrees:
            guard length >= 3 else { return nil }
            deg = Double(UInt16(buffer[1]) | UInt16(buffer[2]) << 8)
        }
        
        if deg >= 0.0 && deg <= 360.0 {
            return deg
        }
        return nil
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var overlayWindows: [NSWindow] = []
    var maskLayers: [CAGradientLayer] = []
    var blurredImages: [String: NSImage] = [:]
    
    let sensor = HardwareLidAngleSensor()
    var sensorTimer: DispatchSourceTimer?
    
    // Angle thresholds
    var maxAngleOpen: Double = 118.0
    var minAngleClosed: Double = 35.0
    
    var blurRadius: Double = 50.0
    var coverIcons: Bool = false
    var enable3DTilt: Bool = true
    var progressiveWipe: Bool = true
    
    // Smoothing & Smart Battery Idle Detection
    var currentSmoothedAngle: Double = 125.0
    var lastTargetAngle: Double = 125.0
    var lastAppliedProgress: Double = -1.0
    var isWindowVisible: Bool = false
    
    var liveAngleMenuItem: NSMenuItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusMenu()
        setupOverlayWindows()
        registerNotifications()
        startSensorPolling()
    }
    
    func setupStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusButton(angle: 125.0)
        
        let menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "✨ Mac Duo Wallpaper Blur", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        let angleItem = NSMenuItem(title: "📐 زاویه لولا: در حال خواندن...", action: nil, keyEquivalent: "")
        angleItem.isEnabled = false
        self.liveAngleMenuItem = angleItem
        menu.addItem(angleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Speed & Trigger Thresholds
        let thresholdMenu = NSMenu()
        let presets: [(String, Double, Double)] = [
            ("⚡ سریع و زودهنگام (شروع از ۱۱۸° تا ۳۵°)", 118.0, 35.0),
            ("🏃 فوق‌العاده سریع (شروع از ۱۲۵° تا ۴۵°)", 125.0, 45.0),
            ("⚖️ استاندارد متعادل (شروع از ۱۰۰° تا ۲۵°)", 100.0, 25.0)
        ]
        for (name, openA, closeA) in presets {
            let item = NSMenuItem(title: name, action: #selector(setThreshold(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [openA, closeA]
            if abs(openA - maxAngleOpen) < 1.0 { item.state = .on }
            thresholdMenu.addItem(item)
        }
        let thresholdItem = NSMenuItem(title: "سرعت و زاویه فعال‌سازی", action: nil, keyEquivalent: "")
        thresholdItem.submenu = thresholdMenu
        menu.addItem(thresholdItem)
        
        // Progressive Blur Mode Toggle
        let progItem = NSMenuItem(title: "🌊 ماتی تدریجی موجی (نصف صفحه و سپس ادامه)", action: #selector(toggleProgressive(_:)), keyEquivalent: "p")
        progItem.target = self
        progItem.state = progressiveWipe ? .on : .off
        menu.addItem(progItem)
        
        // Blur Intensity Menu
        let intensityMenu = NSMenu()
        let intensities: [(String, Double)] = [
            ("ملایم (28px)", 28.0),
            ("استاندارد Duo (50px)", 50.0),
            ("عمیق و سینمایی (75px)", 75.0)
        ]
        for (title, val) in intensities {
            let item = NSMenuItem(title: title, action: #selector(setIntensity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = val
            if abs(val - blurRadius) < 1.0 { item.state = .on }
            intensityMenu.addItem(item)
        }
        let intensityItem = NSMenuItem(title: "شدت ماتی (Blur Depth)", action: nil, keyEquivalent: "")
        intensityItem.submenu = intensityMenu
        menu.addItem(intensityItem)
        
        // 3D Tilt Toggle
        let tiltItem = NSMenuItem(title: "افکت پرسپکتیو سه‌بعدی لولا (3D Tilt)", action: #selector(toggle3DTilt(_:)), keyEquivalent: "t")
        tiltItem.target = self
        tiltItem.state = enable3DTilt ? .on : .off
        menu.addItem(tiltItem)
        
        // Desktop icons placement
        let layerItem = NSMenuItem(title: "مات شدن روی آیکون‌های دسکتاپ", action: #selector(toggleCoverIcons(_:)), keyEquivalent: "")
        layerItem.target = self
        layerItem.state = coverIcons ? .on : .off
        menu.addItem(layerItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let reloadItem = NSMenuItem(title: "🔄 بارگذاری مجدد والپیپر", action: #selector(reloadWallpaper), keyEquivalent: "r")
        reloadItem.target = self
        menu.addItem(reloadItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "خروج (Quit)", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    func updateStatusButton(angle: Double) {
        if let btn = statusItem.button {
            let iconName = angle < 45.0 ? "rectangle.split.2x1" : (angle < 90.0 ? "rectangle.split.2x1.slash" : "rectangle.split.2x1.fill")
            btn.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Mac Duo")
                ?? NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "Mac Duo")
            btn.toolTip = String(format: "Mac Duo Angle: %.1f°", angle)
        }
    }
    
    // MARK: - Smart Zero-Energy Sensor Polling
    func startSensorPolling() {
        guard sensor.isAvailable else {
            liveAngleMenuItem?.title = "⚠️ سنسور لولا شناسایی نشد"
            return
        }
        
        let queue = DispatchQueue(label: "com.antigravity.sensorQueue", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // 35ms polling: reading HID takes 0.00002 seconds
        timer.schedule(deadline: .now(), repeating: .milliseconds(35))
        timer.setEventHandler { [weak self] in
            guard let self = self, let angle = self.sensor.readAngle() else { return }
            
            // Only perform smoothing and UI updates when the angle actually changed!
            let delta = abs(angle - self.lastTargetAngle)
            self.lastTargetAngle = angle
            
            if delta > 0.08 || abs(self.currentSmoothedAngle - angle) > 0.15 {
                let alpha = 0.35
                self.currentSmoothedAngle += (self.lastTargetAngle - self.currentSmoothedAngle) * alpha
                
                DispatchQueue.main.async {
                    self.applyAngleEffect(angle: self.currentSmoothedAngle)
                }
            }
        }
        timer.resume()
        self.sensorTimer = timer
    }
    
    func applyAngleEffect(angle: Double) {
        var progress: Double = 0.0
        if angle <= minAngleClosed {
            progress = 1.0
        } else if angle >= maxAngleOpen {
            progress = 0.0
        } else {
            let linear = (maxAngleOpen - angle) / (maxAngleOpen - minAngleClosed)
            progress = pow(linear, 0.85)
        }
        progress = max(0.0, min(1.0, progress))
        
        // Idle optimization: if already settled at 0.0 or 1.0, skip redundant render cycles
        if abs(progress - lastAppliedProgress) < 0.005 && (progress == 0.0 || progress == 1.0) {
            return
        }
        lastAppliedProgress = progress
        
        // Update menu title
        let percent = Int(progress * 100)
        let stateText: String
        if progress <= 0.02 {
            stateText = "باز (شفاف ۰٪)"
        } else if progress >= 0.98 {
            stateText = "بسته (مات ۱۰۰٪)"
        } else {
            stateText = "مات \(percent)٪"
        }
        liveAngleMenuItem?.title = String(format: "📐 زاویه لولا: %.1f° (%@)", angle, stateText)
        
        // Sleep/Hide Window optimization: When fully open (0%), hide the window completely so GPU does ZERO work
        if progress <= 0.001 {
            if isWindowVisible {
                for win in overlayWindows { win.alphaValue = 0.0; win.orderOut(nil) }
                isWindowVisible = false
            }
            return
        } else {
            if !isWindowVisible {
                for win in overlayWindows { win.orderFront(nil) }
                isWindowVisible = true
            }
        }
        
        // Update window overlays & progressive gradient mask
        for (i, win) in overlayWindows.enumerated() {
            guard let view = win.contentView else { continue }
            
            if progressiveWipe {
                win.alphaValue = 1.0
                if i < maskLayers.count {
                    let mask = maskLayers[i]
                    let lead = CGFloat(progress * 1.5 - 0.2)
                    let trail = max(0.0, lead - 0.45)
                    
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    mask.locations = [
                        NSNumber(value: Double(trail)),
                        NSNumber(value: Double(lead))
                    ]
                    mask.opacity = Float(min(1.0, progress * 2.5))
                    CATransaction.commit()
                }
            } else {
                win.alphaValue = CGFloat(progress)
                if i < maskLayers.count {
                    let mask = maskLayers[i]
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    mask.locations = [0.0, 1.0]
                    mask.opacity = 1.0
                    CATransaction.commit()
                }
            }
            
            if enable3DTilt {
                var transform = CATransform3DIdentity
                transform.m34 = -1.0 / 1100.0
                let tiltAngle = CGFloat(progress * 0.14)
                transform = CATransform3DRotate(transform, tiltAngle, 1, 0, 0)
                let scale = CGFloat(1.0 - (progress * 0.05))
                transform = CATransform3DScale(transform, scale, scale, 1.0)
                view.layer?.transform = transform
            } else {
                view.layer?.transform = CATransform3DIdentity
            }
        }
    }
    
    // MARK: - Overlay Windows & Wallpaper
    func targetWindowLevel() -> NSWindow.Level {
        if coverIcons {
            return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        } else {
            return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        }
    }
    
    func setupOverlayWindows() {
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        maskLayers.removeAll()
        
        for screen in NSScreen.screens {
            let win = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = false
            win.ignoresMouseEvents = true
            win.level = targetWindowLevel()
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            
            let imageView = NSImageView(frame: win.contentView?.bounds ?? .zero)
            imageView.wantsLayer = true
            imageView.autoresizingMask = [.width, .height]
            imageView.imageScaling = .scaleAxesIndependently
            
            let gradientMask = CAGradientLayer()
            gradientMask.frame = screen.frame
            gradientMask.startPoint = CGPoint(x: 0.5, y: 0.0)
            gradientMask.endPoint = CGPoint(x: 0.5, y: 1.0)
            gradientMask.colors = [
                NSColor.white.cgColor,
                NSColor.clear.cgColor
            ]
            gradientMask.locations = [0.0, 0.0]
            
            imageView.layer?.mask = gradientMask
            maskLayers.append(gradientMask)
            
            win.contentView = imageView
            win.alphaValue = 0.0
            overlayWindows.append(win)
        }
        
        updateOverlayContents()
    }
    
    func updateOverlayContents() {
        for (i, screen) in NSScreen.screens.enumerated() {
            guard i < overlayWindows.count else { continue }
            let win = overlayWindows[i]
            guard let imageView = win.contentView as? NSImageView else { continue }
            
            if i < maskLayers.count {
                maskLayers[i].frame = CGRect(origin: .zero, size: screen.frame.size)
            }
            
            let cacheKey = "\(screen.frame.width)x\(screen.frame.height)_\(blurRadius)"
            if let cached = blurredImages[cacheKey] {
                imageView.image = cached
                continue
            }
            
            if let url = NSWorkspace.shared.desktopImageURL(for: screen) {
                DispatchQueue.global(qos: .userInitiated).async {
                    let blurred = self.generateBlurredImage(fromURL: url, targetSize: screen.frame.size, radius: self.blurRadius)
                    DispatchQueue.main.async {
                        self.blurredImages[cacheKey] = blurred
                        imageView.image = blurred
                    }
                }
            }
        }
    }
    
    func generateBlurredImage(fromURL url: URL, targetSize: CGSize, radius: Double) -> NSImage? {
        guard let ciImage = CIImage(contentsOf: url) else { return nil }
        
        let scaleX = targetSize.width / ciImage.extent.width
        let scaleY = targetSize.height / ciImage.extent.height
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let clamped = scaled.clampedToExtent()
        
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return nil }
        blurFilter.setValue(clamped, forKey: kCIInputImageKey)
        blurFilter.setValue(radius, forKey: kCIInputRadiusKey)
        
        guard let blurred = blurFilter.outputImage,
              let colorFilter = CIFilter(name: "CIColorControls") else { return nil }
        colorFilter.setValue(blurred, forKey: kCIInputImageKey)
        colorFilter.setValue(1.10, forKey: kCIInputSaturationKey)
        colorFilter.setValue(-0.05, forKey: kCIInputBrightnessKey)
        
        let context = CIContext(options: nil)
        guard let output = colorFilter.outputImage?.cropped(to: CGRect(origin: .zero, size: targetSize)),
              let cgImage = context.createCGImage(output, from: CGRect(origin: .zero, size: targetSize)) else {
            return nil
        }
        
        return NSImage(cgImage: cgImage, size: targetSize)
    }
    
    // MARK: - Actions
    @objc func setThreshold(_ sender: NSMenuItem) {
        if let arr = sender.representedObject as? [Double], arr.count == 2 {
            maxAngleOpen = arr[0]
            minAngleClosed = arr[1]
            if let parent = sender.menu {
                for item in parent.items { item.state = (item == sender) ? .on : .off }
            }
        }
    }
    
    @objc func toggleProgressive(_ sender: NSMenuItem) {
        progressiveWipe.toggle()
        sender.state = progressiveWipe ? .on : .off
    }
    
    @objc func setIntensity(_ sender: NSMenuItem) {
        if let val = sender.representedObject as? Double {
            blurRadius = val
            if let parent = sender.menu {
                for item in parent.items { item.state = (item == sender) ? .on : .off }
            }
            blurredImages.removeAll()
            updateOverlayContents()
        }
    }
    
    @objc func toggle3DTilt(_ sender: NSMenuItem) {
        enable3DTilt.toggle()
        sender.state = enable3DTilt ? .on : .off
    }
    
    @objc func toggleCoverIcons(_ sender: NSMenuItem) {
        coverIcons.toggle()
        sender.state = coverIcons ? .on : .off
        setupOverlayWindows()
    }
    
    @objc func reloadWallpaper() {
        blurredImages.removeAll()
        updateOverlayContents()
    }
    
    @objc func quitApp() {
        sensorTimer?.cancel()
        sensorTimer = nil
        NSApp.terminate(nil)
    }
    
    func registerNotifications() {
        let wsNC = NSWorkspace.shared.notificationCenter
        wsNC.addObserver(self, selector: #selector(handleWallpaperChange), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenChange), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    
    @objc func handleWallpaperChange() {
        DispatchQueue.main.async { self.reloadWallpaper() }
    }
    
    @objc func handleScreenChange() {
        DispatchQueue.main.async { self.setupOverlayWindows() }
    }
}

// Start Application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
