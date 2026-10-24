import SwiftUI
import CoreMotion
import simd

enum AirSlidePreferences {
    static var defaults: UserDefaults {
        #if AIRSLIDE_TESTING
        return UserDefaults(suiteName: "io.github.tarabcak.airslide.tests")!
        #else
        return UserDefaults.standard
        #endif
    }
}

/// The relay address and key live in a small KEY=VALUE file, never in the app.
enum RelayConfig {
    static let localDefault = "http://127.0.0.1:8094"
    static func file(local: Bool) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/airslide/" + (local ? "local-relay.env" : "relay.env"))
    }
    static func values(in text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { continue }
            var value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let quote = value.first, quote == value.last, quote == "\"" || quote == "'" { value = String(value.dropFirst().dropLast()) }
            result[trimmed[..<equals].trimmingCharacters(in: .whitespaces)] = value
        }
        return result
    }
    /// The key travels as a bearer token, so plain HTTP is allowed only to this Mac.
    static func relayURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), let host = url.host else { return nil }
        return url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) ? url : nil
    }
}

struct SwingDetector {
    var threshold = 1.8
    var negativeThreshold: Double?
    var cooldown = 1.2
    var lastFire = -Double.infinity
    var quietSince: Double?
    var armed = false
    mutating func update(value: Double, time: Double) -> Int? {
        if abs(value) < min(threshold, negativeThreshold ?? threshold) * 0.25 {
            if quietSince == nil { quietSince = time }
            if time - quietSince! > 0.35 && time - lastFire > cooldown { armed = true }
        } else { quietSince = nil }
        guard armed, (value > threshold || value < -(negativeThreshold ?? threshold)), time - lastFire > cooldown else { return nil }
        armed = false; lastFire = time
        return value > 0 ? 1 : -1
    }
}

enum SetupStep: Int, CaseIterable {
    case connect, grip, calibrateRight, calibrateLeft, practice, ready
    var title: String { ["Connect", "Find your grip", "Right swing", "Left swing", "Try it out", "Ready to present"][rawValue] }
    var symbol: String { ["airpodspro", "hand.draw", "arrow.right", "arrow.left", "arrow.left.arrow.right", "checkmark.seal"][rawValue] }
}

@MainActor final class Controller: NSObject, ObservableObject, CMHeadphoneMotionManagerDelegate {
    @Published var setup = !AirSlidePreferences.defaults.bool(forKey: "setupComplete")
    @Published var step: SetupStep = .connect
    @Published var tab = "Control"
    @Published var status = "Connect your AirPods to this Mac."
    @Published var delivery = "Ready when you are"
    @Published var enabled = false { didSet { detector = SwingDetector() } }
    @Published var monitoring = false
    @Published var streaming = false
    @Published var headphonesConnected = false
    @Published var motionAvailable = true
    @Published var permission: CMAuthorizationStatus = .notDetermined
    @Published var permissionRequested = false
    private var connectionObserver: Timer?
    private var attemptedThisConnection = false
    private var streamEpoch = 0
    private(set) var recoveryAttempts = 0
    var connectionLabel: String { headphonesConnected ? "Connected" : "Not connected" }
    var permissionLabel: String {
        switch permission {
        case .authorized: return "Allowed"
        case .denied: return "Access denied"
        case .restricted: return "Restricted"
        case .notDetermined: return permissionRequested ? "Awaiting approval" : headphonesConnected ? "Ready to allow" : "Waiting for AirPods"
        @unknown default: return "Unavailable"
        }
    }
    var permissionHelp: String {
        switch permission {
        case .authorized: return streaming ? "Motion access is enabled and receiving movement." : headphonesConnected ? "Access is enabled. Waiting for movement; try wearing your AirPods." : "Access is enabled. Reconnect your AirPods to continue."
        case .denied: return "Enable AirSlide in System Settings → Privacy & Security → Motion & Fitness."
        case .restricted: return "Motion access is restricted on this Mac. Check with its administrator."
        default: return permissionRequested ? "Choose Allow in the macOS permission prompt." : "macOS will ask for permission when your AirPods connect."
        }
    }
    func observeConnection() {
        #if !AIRSLIDE_TESTING
        guard connectionObserver == nil else { return }
        motion.delegate = self
        refreshPermission()
        motion.startConnectionStatusUpdates()
        connectionObserver = Timer.scheduledTimer(withTimeInterval:0.5,repeats:true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.checkAvailability(self.motion.isDeviceMotionAvailable)
                self.refreshPermission()
            }
        }
        #endif
    }
    func refreshPermission() {
        applyPermission(CMHeadphoneMotionManager.authorizationStatus())
    }
    func applyPermission(_ value: CMAuthorizationStatus) {
        permission = value
        if permission != .notDetermined { permissionRequested = false }
        if permission == .denied || permission == .restricted {
            if monitoring { stop() }
        } else if permission == .authorized && headphonesConnected && !monitoring {
            start()
        }
    }
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in self?.connectionChanged(true) }
    }
    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in self?.connectionChanged(false) }
    }
    func checkAvailability(_ available: Bool) {
        motionAvailable = available
        if !available && headphonesConnected {
            streaming = false; enabled = false; calibrating = false
            status = "Motion unavailable. Check your AirPods connection."
        }
    }
    var controlState: String { !headphonesConnected ? "Disconnected" : !motionAvailable ? "Motion unavailable" : !streaming ? "Motion paused" : enabled ? "Live" : "Standby" }
    var controlHelp: String {
        if !headphonesConnected { return "Connect your AirPods to enable gesture control." }
        if !streaming { return "Motion is unavailable. Check your AirPods and motion permission." }
        return enabled ? "Gestures move slides on every open screen." : "Off while you prepare. Turn on when you’re ready."
    }
    func connectionChanged(_ connected: Bool) {
        headphonesConnected = connected
        if connected {
            if !attemptedThisConnection && permission != .denied && permission != .restricted {
                attemptedThisConnection = true; start()
            }
        } else {
            recoveryAttempts = 0
            attemptedThisConnection = false; permissionRequested = false
            if calibrating { calibrationPhase = "AirPods disconnected. Reconnect and try again." }
            stop(); side = "No AirPod connected"; reference = nil
            orientation = simd_quatf(angle:0,axis:[0,1,0])
            status = "AirPods disconnected. Reconnect to resume."
        }
    }
    @Published var threshold = AirSlidePreferences.defaults.object(forKey: "swingThreshold") as? Double ?? 1.8 { didSet { detector = SwingDetector(); saveSettings() } }
    @Published var leftThreshold = AirSlidePreferences.defaults.object(forKey: "leftThreshold") as? Double ?? 1.8 { didSet { detector = SwingDetector(); saveSettings() } }
    @Published var rightCalibrated = AirSlidePreferences.defaults.bool(forKey: "bilateralCalibration")
    @Published var cooldown = AirSlidePreferences.defaults.object(forKey: "swingCooldown") as? Double ?? 1.2 { didSet { saveSettings() } }
    @Published var axis = AirSlidePreferences.defaults.integer(forKey: "swingAxis") { didSet { detector = SwingDetector(); saveSettings() } }
    @Published var inverted = AirSlidePreferences.defaults.bool(forKey: "swingInverted") { didSet { detector = SwingDetector(); saveSettings() } }
    @Published var reverseDirections = AirSlidePreferences.defaults.bool(forKey: "reverseDirections") { didSet { detector = SwingDetector(); AirSlidePreferences.defaults.set(reverseDirections, forKey: "reverseDirections") } }
    @Published var reading = 0.0
    @Published var side = "Waiting for sensor"
    @Published var orientation = simd_quatf(angle: 0, axis: [0,1,0])
    @Published var calibrationPhase = ""
    @Published var calibrationProgress = 0.0
    @Published var calibrating = false
    @Published var calibrated = AirSlidePreferences.defaults.bool(forKey: "bilateralCalibration")
    @Published var practiceNext = false
    @Published var practicePrev = false
    @Published var practiceMessage = "Try a right swing, rest, then a left swing."
    @Published var lastGesture = ""
    @Published var gesturePulse = 0
    @Published var viewers: Int?
    @Published var earDetectionConfirmed = false
    @Published var showHand = AirSlidePreferences.defaults.object(forKey: "showHand") as? Bool ?? true { didSet { AirSlidePreferences.defaults.set(showHand, forKey: "showHand") } }
    private let motion = CMHeadphoneMotionManager()
    private var detector = SwingDetector()
    private var reference: simd_quatf?
    private var latestQuaternion = simd_quatf(angle: 0, axis: [0,1,0])
    private var lastSample = -Double.infinity
    private var lastPublished = 0.0
    private var calibrationStart = 0.0
    private var calibrationPeak = 0.0
    private var calibrationSign = 1.0
    private var calibrationAxis = 2
    private var watchdog: Timer?
    private var sending = false
    @Published var localRehearsal = AirSlidePreferences.defaults.bool(forKey: "localRehearsal") {
        didSet {
            enabled = false
            delivery = "Ready when you are"
            AirSlidePreferences.defaults.set(localRehearsal, forKey: "localRehearsal")
            reloadConfig()
        }
    }
    var configPath: String { "~/.config/airslide/" + RelayConfig.file(local: localRehearsal).lastPathComponent }
    @Published private var config: [String: String] = [:]
    var endpoint: String { config["REMOTE_URL"] ?? (localRehearsal ? RelayConfig.localDefault : "") }
    var relayURL: URL? { RelayConfig.relayURL(endpoint) }
    /// Read at launch, on navigation, when the destination changes and before each send, so edits apply without a restart.
    func reloadConfig() {
        config = RelayConfig.values(in: (try? String(contentsOf: RelayConfig.file(local: localRehearsal), encoding: .utf8)) ?? "")
    }
    override init() {
        super.init()
        reloadConfig()
    }
    var practicing: Bool { setup && step == .practice }
    var sensitivity: Double {
        get { 6.6 - threshold }
        set { let ratio = leftThreshold / max(threshold, 0.1); threshold = 6.6 - newValue; leftThreshold = min(6, max(0.6, threshold * ratio)) }
    }
    private var token: String { config["REMOTE_TOKEN"] ?? "" }
    func saveSettings() {
        let d = AirSlidePreferences.defaults
        d.set(leftThreshold, forKey: "leftThreshold")
        d.set(threshold, forKey: "swingThreshold"); d.set(cooldown, forKey: "swingCooldown")
        d.set(axis, forKey: "swingAxis"); d.set(inverted, forKey: "swingInverted")
    }
    func start(at now: Double = ProcessInfo.processInfo.systemUptime) {
        guard !monitoring, permission != .denied, permission != .restricted else { return }
        permissionRequested = permission == .notDetermined
        streamEpoch += 1; let epoch = streamEpoch
        enabled = false; detector = SwingDetector(); reference = nil
        monitoring = true; lastSample = now
        status = "Waiting for motion permission and AirPods…"
        #if !AIRSLIDE_TESTING
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, error in
            Task { @MainActor in
                guard let self, self.monitoring, self.streamEpoch == epoch else { return }
                if let error { self.status = error.localizedDescription; self.enabled = false; self.streaming = false; self.refreshPermission(); return }
                guard let data else { return }
                self.receive(data)
            }
        }
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        #endif
    }
    private func receive(_ data: CMDeviceMotion) {
        let now = ProcessInfo.processInfo.systemUptime
        let newSide: String
        switch data.sensorLocation {
        case .headphoneLeft: newSide = "Left AirPod"
        case .headphoneRight: newSide = "Right AirPod"
        default: newSide = "AirPod · side unavailable"
        }
        let q = data.attitude.quaternion
        handleSample(values: [data.rotationRate.x, data.rotationRate.y, data.rotationRate.z],
                     quaternion: simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w)),
                     source: newSide, at: now)
    }
    func handleSample(values: [Double], quaternion: simd_quatf, source newSide: String, at now: Double) {
        guard values.count == 3, values.allSatisfy({ $0.isFinite }), (0...2).contains(axis) else { return }
        guard quaternion.vector.x.isFinite, quaternion.vector.y.isFinite, quaternion.vector.z.isFinite, quaternion.vector.w.isFinite, simd_length(quaternion.vector) > 0.001 else { return }
        if side != newSide {
            let savedSide = AirSlidePreferences.defaults.string(forKey: "calibratedSide")
            if streaming || ((calibrated || rightCalibrated) && savedSide != newSide) {
                enabled = false; calibrated = false; rightCalibrated = false; calibrating = false
                AirSlidePreferences.defaults.set(false, forKey: "bilateralCalibration")
                status = "Sensor switched. Recalibrate for this AirPod."
            }
            side = newSide; reference = nil; detector = SwingDetector()
        }
        headphonesConnected = true; motionAvailable = true; permission = .authorized; permissionRequested = false
        streaming = true; lastSample = now; recoveryAttempts = 0
        latestQuaternion = simd_normalize(quaternion)
        if reference == nil { reference = latestQuaternion }
        if now - lastPublished > 1.0 / 30 {
            orientation = reference!.inverse * latestQuaternion
            reading = values[axis]; lastPublished = now
        }
        if calibrating {
            let elapsed = now - calibrationStart
            if elapsed >= 2 && elapsed < 4.5 {
                for (index, value) in values.enumerated() where (step != .calibrateLeft || index == axis) && abs(value) > calibrationPeak {
                    calibrationPeak = abs(value); calibrationSign = value; calibrationAxis = index
                }
            }
            return
        }
        detector.threshold = inverted ? leftThreshold : threshold
        detector.negativeThreshold = inverted ? threshold : leftThreshold
        detector.cooldown = cooldown
        guard calibrated && ((enabled && !setup) || practicing) else { return }
        if let sign = detector.update(value: values[axis], time: now) {
            let direction = (((sign > 0) != inverted) != reverseDirections) ? "next" : "prev"
            lastGesture = direction; gesturePulse += 1
            if practicing {
                if direction == "next" { practiceNext = true } else { practicePrev = true }
                practiceMessage = direction == "next" ? "Right swing detected. Now rest, then swing left." : "Left swing detected. Return to a relaxed grip."
            } else { send(direction) }
        }
    }
    func tick(at now: Double = ProcessInfo.processInfo.systemUptime) {
        if monitoring && now - lastSample > 2 {
            streaming = false; enabled = false
            status = "Motion paused. Check AirPods connection and Automatic Ear Detection."
            if calibrating { calibrating = false; calibrated = false; calibrationPhase = "Connection interrupted. Reconnect and try again." }
            if now - lastSample >= 5 && headphonesConnected && motionAvailable && permission == .authorized && recoveryAttempts < 3 {
                recoveryAttempts += 1
                stop(); start(at: now)
                status = "Reconnecting motion… (\(recoveryAttempts)/3)"
            } else if recoveryAttempts >= 3 {
                status = "No motion received. Wear both AirPods briefly, then choose Retry motion."
            }
        }
        guard calibrating else { return }
        let elapsed = now - calibrationStart
        calibrationProgress = min(1, elapsed / 6)
        calibrationPhase = elapsed < 2 ? "Hold still… \(max(1, Int(ceil(2-elapsed))))" : elapsed < 4.5 ? (step == .calibrateLeft ? "← Swing LEFT once" : "Swing RIGHT once →") : "Return gently. Hold still."
        if elapsed >= 6 {
            calibrating = false; detector = SwingDetector()
            if calibrationPeak >= 0.6 {
                if step == .calibrateLeft {
                    guard (calibrationSign < 0) != inverted else {
                        calibrationPhase = "That matched your right swing. Try the opposite wrist turn."; return
                    }
                    leftThreshold = min(6, max(0.6, calibrationPeak * 0.55)); calibrated = true
                    calibrationPhase = "Left swing captured. Both directions are ready."
                    AirSlidePreferences.defaults.set(true, forKey: "bilateralCalibration")
                } else {
                    axis = calibrationAxis; inverted = calibrationSign < 0; reverseDirections = false
                    threshold = min(6, max(0.6, calibrationPeak * 0.55)); rightCalibrated = true
                    calibrationPhase = "Right swing captured. Continue to the left swing."
                }
                AirSlidePreferences.defaults.set(side, forKey: "calibratedSide"); recenter()
            } else { calibrated = false; calibrationPhase = "That was too subtle. Try a clearer wrist turn." }
        }
    }
    func stop() {
        streamEpoch += 1
        monitoring = false; streaming = false; enabled = false; calibrating = false
        motion.stopDeviceMotionUpdates(); watchdog?.invalidate(); watchdog = nil
        status = "Motion stopped"
    }
    func retryMotion() {
        recoveryAttempts = 0
        stop(); start()
    }
    func recenter() { reference = latestQuaternion; orientation = simd_quatf(angle: 0, axis: [0,1,0]) }
    func calibrate(at now: Double = ProcessInfo.processInfo.systemUptime) {
        guard streaming, step != .calibrateLeft || rightCalibrated else { calibrationPhase = "Connect your AirPod before calibrating."; return }
        if step != .calibrateLeft { rightCalibrated = false }
        AirSlidePreferences.defaults.set(false, forKey: "bilateralCalibration")
        enabled = false; calibrated = false; calibrating = true; calibrationPeak = 0
        calibrationProgress = 0; calibrationStart = now
        calibrationPhase = "Hold still… 2"; detector = SwingDetector(); recenter()
    }
    func beginSetup() {
        enabled = false; setup = true; step = .connect; calibrating = false; calibrated = false; rightCalibrated = false
        AirSlidePreferences.defaults.set(false, forKey: "bilateralCalibration")
        AirSlidePreferences.defaults.set(false, forKey: "setupComplete")
        practiceNext = false; practicePrev = false; earDetectionConfirmed = false
        detector = SwingDetector(); observeConnection()
    }
    func advance() {
        guard canAdvance, !calibrating else { return }
        if let next = SetupStep(rawValue: step.rawValue+1) {
            step = next; calibrationPhase = ""; calibrationProgress = 0; detector = SwingDetector()
            if next == .practice { practiceNext = false; practicePrev = false; practiceMessage = "Try a right swing, rest, then a left swing." }
        } else { finishSetup() }
    }
    func finishSetup() {
        guard calibrated, practiceNext, practicePrev else { return }
        AirSlidePreferences.defaults.set(true, forKey: "setupComplete")
        saveSettings(); setup = false; enabled = false; tab = "Control"
    }
    func back() { calibrating = false; calibrationPhase = ""; calibrationProgress = 0; if let previous = SetupStep(rawValue: step.rawValue-1) { step = previous }; detector = SwingDetector() }
    var canAdvance: Bool {
        switch step {
        case .connect: return streaming
        case .grip: return streaming && earDetectionConfirmed
        case .calibrateRight: return streaming && rightCalibrated && !calibrating
        case .calibrateLeft: return streaming && calibrated && !calibrating
        case .practice: return streaming && calibrated && practiceNext && practicePrev
        case .ready: return calibrated && practiceNext && practicePrev
        }
    }
    func send(_ direction: String) {
        guard !sending, !setup else { return }
        reloadConfig()
        guard token.count >= 32, let base = relayURL else { delivery = "Relay not configured. Add REMOTE_URL and REMOTE_TOKEN to \(configPath)."; return }
        var request = URLRequest(url: base.appendingPathComponent("api/command"))
        request.httpMethod = "POST"; request.timeoutInterval = 4
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var command = ["direction":direction,"id":UUID().uuidString]
        if side == "Left AirPod" { command["side"] = "left" }
        if side == "Right AirPod" { command["side"] = "right" }
        request.httpBody = try? JSONSerialization.data(withJSONObject:command)
        sending = true
        Task {
            defer { sending = false }
            do {
                let (body,response) = try await URLSession.shared.data(for:request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { delivery = "Command not accepted. Check the connection."; return }
                let result = try? JSONSerialization.jsonObject(with: body) as? [String:Any]
                let count = result?["delivered"] as? Int ?? 0; viewers = count
                delivery = count > 0 ? "\(direction == "next" ? "Next" : "Previous") sent to \(count) \(count == 1 ? "screen" : "screens")" : "No screens connected. Open the presentation first."
            } catch { delivery = "Delivery uncertain. Check the slide before retrying." }
        }
    }
}

#if !AIRSLIDE_TESTING
@main struct AirSlideApp: App {
    @StateObject private var controller = Controller()
    var body: some Scene {
        WindowGroup("AirSlide") { AirSlideView(c: controller).preferredColorScheme(.dark) }
            .windowResizability(.contentSize)
    }
}

#endif
