import Foundation
import simd

@main struct BehaviorTests {
    @MainActor static func main() {
        let defaults = AirSlidePreferences.defaults
        defaults.removePersistentDomain(forName:"io.github.tarabcak.airslide.tests")
        defer { defaults.removePersistentDomain(forName:"io.github.tarabcak.airslide.tests") }
        let config = RelayConfig.values(in:"# relay\nREMOTE_URL = \"https://relay.example\"\nREMOTE_TOKEN=abc=def\n\nBROKEN")
        assert(config["REMOTE_URL"] == "https://relay.example" && config["REMOTE_TOKEN"] == "abc=def" && config["BROKEN"] == nil)
        assert(RelayConfig.relayURL("https://relay.example") != nil && RelayConfig.relayURL(RelayConfig.localDefault) != nil)
        assert(RelayConfig.relayURL("http://relay.example") == nil, "The key must never travel over plain HTTP to another host")
        assert(RelayConfig.relayURL("") == nil && RelayConfig.relayURL("relay.example") == nil)
        var detector = SwingDetector()
        assert(detector.update(value:3,time:0) == nil, "Must settle before arming")
        assert(detector.update(value:0,time:0.1) == nil)
        assert(detector.update(value:0,time:0.5) == nil)
        assert(detector.update(value:3,time:0.6) == 1)
        assert(detector.update(value:-3,time:0.8) == nil, "Return swing must not fire")
        _ = detector.update(value:0,time:1.9); _ = detector.update(value:0,time:2.3)
        assert(detector.update(value:-3,time:2.4) == -1)
        let connection = Controller()
        assert(connection.connectionLabel == "Not connected" && connection.permissionLabel == "Waiting for AirPods")
        connection.connectionChanged(true)
        assert(connection.headphonesConnected && connection.monitoring && connection.permissionRequested)
        assert(connection.permissionLabel == "Awaiting approval")
        connection.connectionChanged(true) // duplicate connection must not reset a running stream
        connection.applyPermission(.denied)
        assert(!connection.monitoring && !connection.streaming && connection.permissionLabel == "Access denied")
        connection.connectionChanged(true)
        assert(!connection.monitoring, "Denied access must never automatically re-request")
        connection.applyPermission(.authorized)
        assert(connection.monitoring && connection.permissionLabel == "Allowed")
        connection.enabled = true; connection.calibrating = true
        connection.connectionChanged(false)
        assert(!connection.monitoring && !connection.streaming && !connection.enabled && !connection.calibrating)
        assert(connection.permissionLabel == "Allowed", "Permission is independent of connection")
        connection.applyPermission(.restricted); connection.connectionChanged(true)
        assert(!connection.monitoring && connection.permissionLabel == "Restricted")
        connection.applyPermission(.authorized)
        connection.connectionChanged(true); connection.streaming = true; connection.side = "Right AirPod"
        connection.enabled = true
        connection.checkAvailability(false)
        assert(connection.controlState == "Motion unavailable" && connection.headphonesConnected)
        assert(!connection.streaming && !connection.enabled)
        connection.checkAvailability(true)
        assert(connection.headphonesConnected && connection.controlState == "Motion paused", "Availability recovery must not need a new connection callback")
        connection.connectionChanged(false)
        assert(connection.controlState == "Disconnected" && connection.side == "No AirPod connected")
        connection.checkAvailability(true)
        assert(!connection.headphonesConnected, "Availability alone must not claim a new connection")
        connection.stop()
        let recovery = Controller()
        recovery.permission = .authorized; recovery.headphonesConnected = true
        recovery.start(at: 0); recovery.enabled = true
        recovery.tick(at: 2.1)
        assert(!recovery.enabled && recovery.recoveryAttempts == 0)
        recovery.tick(at: 5)
        assert(recovery.monitoring && recovery.recoveryAttempts == 1)
        recovery.tick(at: 6)
        assert(recovery.recoveryAttempts == 1, "Retry must allow time for first sample")
        recovery.tick(at: 10); recovery.tick(at: 15); recovery.tick(at: 30)
        assert(recovery.recoveryAttempts == 3, "Automatic recovery must be bounded")
        recovery.handleSample(values:[0,0,0],quaternion:simd_quatf(angle:0,axis:[0,1,0]),source:"Right AirPod",at:31)
        assert(recovery.streaming && recovery.recoveryAttempts == 0 && !recovery.enabled)
        recovery.connectionChanged(false); recovery.tick(at:40)
        assert(!recovery.monitoring && recovery.recoveryAttempts == 0)
        recovery.stop()
        let c = Controller(); c.monitoring = true
        let q = simd_quatf(angle:0,axis:[0,1,0])
        func sample(_ time:Double,_ value:Double = 0,_ side:String = "Right AirPod") {
            c.handleSample(values:[0,0,value],quaternion:q,source:side,at:time)
        }
        c.step = .calibrateRight
        sample(100); c.calibrate(at:100)
        sample(101,9) // settling period must not calibrate
        sample(102.5,3); sample(104,0); sample(105.5,0); c.tick(at:106)
        assert(c.rightCalibrated && !c.calibrated && !c.calibrating && c.axis == 2 && !c.inverted)
        assert(abs(c.threshold-1.65) < 0.01)
        c.advance(); assert(c.step == .calibrateLeft)
        c.calibrate(at:106)
        sample(108.5,3); sample(110); sample(111.5); c.tick(at:112)
        assert(!c.calibrated && !c.canAdvance, "Left must oppose right")
        c.calibrate(at:112)
        sample(114.5,-2); sample(116); sample(117.5); c.tick(at:118)
        assert(c.calibrated && abs(c.leftThreshold-1.1)<0.01)
        c.advance(); assert(c.step == .practice)

        sample(127); sample(127.5); sample(127.6,3)
        assert(c.practiceNext && !c.practicePrev && c.viewers == nil, "Practice cannot send slide commands")
        sample(129); sample(129.5); sample(129.6,-3)
        assert(c.practicePrev && c.canAdvance)
        c.reverseDirections = true
        sample(131); sample(131.5); sample(131.6,-1.3)
        assert(c.lastGesture == "next", "Reverse preserves the weaker physical left threshold")
        c.reverseDirections = false
        c.advance(); c.finishSetup()
        assert(!c.setup && !c.enabled && defaults.bool(forKey:"setupComplete"))
        c.enabled = true; c.tick(at:134)
        assert(!c.streaming && c.calibrated, "Gap should disarm without discarding same-earbud calibration")
        sample(135,0,"Left AirPod")
        assert(!c.enabled && !c.calibrated, "Source change must disarm and invalidate calibration")
        c.step = .calibrateRight; c.calibrate(at:135); c.tick(at:138)
        assert(!c.calibrating && !c.streaming, "Disconnect must end calibration")
        c.beginSetup()
        assert(!c.calibrated && !defaults.bool(forKey:"setupComplete"), "Restart setup must require a fresh calibration")
        c.step = .calibrateRight
        sample(200); c.calibrate(at:200)
        sample(202.5,3); sample(204); sample(205.5); c.tick(at:206)
        assert(c.rightCalibrated)
        c.advance(); c.tick(at:209); sample(210,0,"Left AirPod")
        assert(!c.rightCalibrated && !c.canAdvance, "A sensor switch after a gap invalidates partial calibration")
        c.calibrate(at:210); assert(!c.calibrating)
        c.threshold = 0.6; c.leftThreshold = 6; c.sensitivity = 0.6
        assert(c.leftThreshold <= 6 && c.threshold <= 6)
        c.stop()
        print("PASS: relay config, settle, cooldown, direction, calibration clock, practice isolation, persistence, source switch, disconnect")
    }
}
