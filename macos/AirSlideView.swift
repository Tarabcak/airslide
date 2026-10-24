import SwiftUI

private let accent = Color(red:0.38,green:0.61,blue:1)
private let muted = Color(red:0.60,green:0.64,blue:0.72)
private let panel = Color(red:0.12,green:0.125,blue:0.14)

struct AirSlideView: View {
    @ObservedObject var c: Controller
    @State private var settingsTab = "Gestures"
    @State private var pulseDirection = ""
    var body: some View {
        HStack(spacing:0) {
            sidebar
            VStack(alignment:.leading,spacing:20) {
                header
                if c.setup { onboarding }
                else if c.tab == "Settings" { settings }
                else { dashboard }
            }.padding(30).frame(width:790,height:800)
        }.background(Color(red:0.085,green:0.09,blue:0.105))
            .frame(width:1010,height:800)
            .tint(accent)
            .onAppear { c.observeConnection(); c.reloadConfig() }
            .task(id:c.gesturePulse) {
                guard c.gesturePulse > 0 else { return }
                withAnimation(.easeOut(duration:0.1)) { pulseDirection = c.lastGesture }
                do { try await Task.sleep(for:.milliseconds(220)) } catch { return }
                withAnimation(.easeOut(duration:0.65)) { pulseDirection = "" }
            }
    }
    private var sidebar: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:10) {
                Image(nsImage:NSImage(named:"AppIcon") ?? NSImage()).resizable().frame(width:36,height:36)
                Text("AirSlide").font(.system(size:22,weight:.semibold,design:.rounded))
            }.padding(.bottom,7)
            Text("Presentation remote").font(.system(size:11)).foregroundStyle(muted)
            Rectangle().fill(.white.opacity(0.07)).frame(height:1).padding(.vertical,28)
            if c.setup {
                Text("YOUR SETUP").font(.system(size:10,weight:.semibold)).tracking(1.5).foregroundStyle(muted).padding(.bottom,18)
                ForEach(SetupStep.allCases,id:\.rawValue) { step in
                    HStack(spacing:12) {
                        ZStack {
                            Circle().fill(step == c.step ? accent : .white.opacity(0.06)).frame(width:27,height:27)
                            if step.rawValue < c.step.rawValue { Image(systemName:"checkmark").foregroundStyle(accent).font(.system(size:11,weight:.bold)) }
                            else { Text("\(step.rawValue+1)").font(.system(size:11,weight:.semibold)).foregroundStyle(step == c.step ? .white : muted) }
                        }
                        Text(step.title).font(.system(size:12,weight:step == c.step ? .semibold : .regular)).foregroundStyle(step == c.step ? .white : muted)
                    }.padding(.vertical,12)
                }
            } else {
                navigation("Control",symbol:"slider.horizontal.3")
                navigation("Settings",symbol:"gearshape")
                Button { c.beginSetup() } label: {
                    Label("Run setup again",systemImage:"arrow.counterclockwise").font(.system(size:12)).foregroundStyle(muted).padding(.vertical,18)
                }.buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing:7) {
                Circle().fill(c.streaming ? Color.green : Color.orange).frame(width:6,height:6)
                Text(c.streaming ? c.side : c.headphonesConnected ? "Connected · motion paused" : "AirPods disconnected").font(.system(size:11,weight:.medium))
            }.foregroundStyle(muted)
            Text("OPEN SOURCE · MIT").font(.system(size:9,weight:.medium)).tracking(1.4).foregroundStyle(muted.opacity(0.6)).padding(.top,14)
        }.padding(22).frame(width:220,height:800).background(.white.opacity(0.025))
    }
    private func navigation(_ title:String,symbol:String) -> some View {
        Button { c.tab = title; c.reloadConfig() } label: {
            HStack { Image(systemName:symbol).frame(width:18); Text(title); Spacer() }
                .font(.system(size:13,weight:.medium)).padding(12)
                .background(c.tab == title ? accent.opacity(0.15) : .clear,in:RoundedRectangle(cornerRadius:9))
                .foregroundStyle(c.tab == title ? accent : muted)
        }.buttonStyle(.plain).padding(.bottom,5)
    }
    private var header: some View {
        HStack(alignment:.top) {
            VStack(alignment:.leading,spacing:7) {
                Text(c.setup ? "Setup · Step \(c.step.rawValue + 1) of 6" : "AirSlide").font(.system(size:12,weight:.medium)).foregroundStyle(muted)
                Text(c.setup ? c.step.title : c.tab == "Settings" ? "Fine-tune your flow." : "Move with intention.")
                    .font(.system(size:28,weight:.semibold)).tracking(-0.5)
                Text(subtitle).font(.system(size:14)).foregroundStyle(muted).fixedSize(horizontal:false,vertical:true)
            }
            Spacer(minLength:8)
            if !c.setup {
                Label(c.controlState,systemImage:!c.headphonesConnected ? "airpodspro" : c.enabled ? "dot.radiowaves.left.and.right" : "pause.circle")
                    .font(.system(size:11,weight:.medium)).padding(.horizontal,12).padding(.vertical,7)
                    .background(c.enabled ? Color.green.opacity(0.13) : .white.opacity(0.06),in:Capsule())
                    .foregroundStyle(!c.streaming ? .orange : c.enabled ? .green : muted)
            }
        }
    }
    private var subtitle: String {
        if !c.setup { return c.tab == "Settings" ? "Small adjustments. A gesture that feels natural." : "One deliberate swing controls every connected screen." }
        switch c.step {
        case .connect: return "Let’s turn your AirPod into a presentation remote."
        case .grip: return "Keep motion connected, then get comfortable with your grip."
        case .calibrateRight: return "First, teach AirSlide your natural right wrist turn."
        case .calibrateLeft: return "Now teach the opposite turn. Keep the same grip."
        case .practice: return "Find your rhythm here. Your slides won’t move during practice."
        case .ready: return "Your gestures are ready. You decide when to go live."
        }
    }
    private func stage(demo:Bool,height:CGFloat = 300) -> some View {
        ZStack {
            LinearGradient(colors:[Color(red:0.12,green:0.16,blue:0.24),Color(red:0.08,green:0.10,blue:0.15)],startPoint:.topLeading,endPoint:.bottomTrailing)
            Circle().fill(accent.opacity(0.075)).frame(width:235,height:235).blur(radius:32)
            MotionScene(orientation:c.orientation,side:c.side,demonstration:demo,showHand:c.showHand && (c.step != .connect || !c.setup),connected:c.streaming, guideDirection:c.step == .calibrateLeft ? -1 : 1, showGuide:c.setup && [.grip,.calibrateRight,.calibrateLeft].contains(c.step))
                .padding(.top,28).padding(.bottom,44).frame(height:height).allowsHitTesting(false)
            VStack {
                HStack {
                    Label(demo ? "MOVEMENT GUIDE" : c.streaming ? "RELATIVE ROTATION" : "AIRPODS PRO",systemImage:demo ? "play.circle" : "view.3d")
                        .font(.system(size:9,weight:.semibold)).tracking(1)
                    Spacer()
                    Text(c.streaming ? c.side : "Sensor not connected").font(.system(size:10))
                }.foregroundStyle(muted)
                Spacer()
                HStack {
                    if demo {
                        Label(c.step == .calibrateLeft ? "Turn your wrist left. Return slowly." : "Turn your wrist right. Return slowly.",systemImage:c.step == .calibrateLeft ? "arrow.turn.up.left" : "arrow.turn.up.right").font(.system(size:12,weight:.medium))
                    } else {
                        Circle().fill(c.streaming ? .green : .orange).frame(width:5,height:5)
                        Text(c.streaming ? "Rotation only · position isn’t tracked" : "Waiting for movement data").font(.system(size:11))
                        Spacer()
                        Button("Set neutral pose") { c.recenter() }.font(.system(size:10)).buttonStyle(.plain)
                    }
                }.foregroundStyle(Color.white.opacity(0.85)).padding(.horizontal,12).padding(.vertical,8).background(.black.opacity(0.22),in:Capsule())
            }.padding(18)
        }.frame(height:height).clipShape(RoundedRectangle(cornerRadius:18))
            .overlay(RoundedRectangle(cornerRadius:18).stroke(.white.opacity(0.06),lineWidth:1))
            
    }
    private var onboarding: some View {
        VStack(alignment:.leading,spacing:16) {
            stage(demo:c.step == .grip || ([.calibrateRight,.calibrateLeft].contains(c.step) && !c.calibrating),height:300)
            Group {
                switch c.step {
                case .connect:
                    VStack(alignment:.leading,spacing:18) {
                        connectionRow("airpodspro", "Connect your AirPods",
                            c.headphonesConnected ? "Your AirPods are connected to this Mac." : "Wear your AirPods and select them in Bluetooth settings.",
                            c.connectionLabel, complete:c.headphonesConnected, pending:!c.headphonesConnected)
                        if !c.headphonesConnected {
                            HStack {
                                Button("Bluetooth settings") { openSettings("x-apple.systempreferences:com.apple.BluetoothSettings") }
                                if c.permission != .denied && c.permission != .restricted {
                                    Button("Check motion connection") { c.stop(); c.start() }
                                }
                            }.padding(.leading,44)
                        }
                        Divider().opacity(0.4)
                        connectionRow("waveform.path", "Allow motion access", c.permissionHelp,
                            c.permissionLabel, complete:c.permission == .authorized,
                            pending:c.permission == .notDetermined)
                        if c.permission == .denied {
                            Button("Open privacy settings") { openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Motion") }.padding(.leading,44)
                        } else if c.headphonesConnected && !c.streaming && c.permission != .restricted {
                            Button(c.permissionRequested ? "Retry permission request" : "Retry motion") { c.stop(); c.start() }.padding(.leading,44)
                        }
                        if c.streaming {
                            Divider().opacity(0.4)
                            Label("You’re connected. Continue to find your grip.",systemImage:"checkmark.circle.fill")
                                .font(.system(size:13,weight:.medium)).foregroundStyle(.green)
                        }
                    }
                case .grip:
                    VStack(alignment:.leading,spacing:18) {
                        instruction("ear.badge.waveform", "Keep motion active", "Turn off Automatic Ear Detection so the AirPod works outside your ear.")
                        HStack(spacing:7) {
                            Image(systemName:"gearshape").foregroundStyle(muted)
                            Text("System Settings")
                            Image(systemName:"chevron.right").font(.system(size:8,weight:.semibold))
                            Text("Your AirPods")
                            Image(systemName:"chevron.right").font(.system(size:8,weight:.semibold))
                            Text("Automatic Ear Detection").foregroundStyle(.white.opacity(0.85))
                        }.font(.system(size:11)).foregroundStyle(muted).padding(.leading,44)
                        Divider().opacity(0.4)
                        instruction("hand.pinch", "Hold one AirPod", "Pinch the stem gently. Keep the same grip as you turn your wrist.")
                        Divider().opacity(0.4)
                        VStack(alignment:.leading,spacing:6) {
                        HStack {
                            Toggle("I’ve taken an AirPod out and motion still works",isOn:$c.earDetectionConfirmed)
                                .font(.system(size:13,weight:.medium)).toggleStyle(.checkbox)
                            Spacer()
                            if c.earDetectionConfirmed { Text("Confirmed").font(.system(size:11,weight:.medium)).foregroundStyle(.green) }
                        }
                        Text("Check this after testing. It confirms you’re ready; it doesn’t change an AirPods setting.").font(.system(size:12)).foregroundStyle(muted)
                        }
                    }
                case .calibrateRight, .calibrateLeft:
                    VStack(alignment:.leading,spacing:14) {
                        HStack {
                            Image(systemName:(c.step == .calibrateRight ? c.rightCalibrated : c.calibrated) ? "checkmark.circle.fill" : "scope").foregroundStyle(c.calibrated ? .green : accent).font(.system(size:24))
                            VStack(alignment:.leading,spacing:5) {
                                Text(c.calibrationPhase.isEmpty ? (c.step == .calibrateLeft ? "Still → left swing → rest" : "Still → right swing → rest") : c.calibrationPhase).font(.system(size:19,weight:.semibold))
                                Text(c.step == .calibrateLeft ? "Keep your grip. On the cue, turn your wrist LEFT once. Hold the end position until asked to return." : "Hold your forearm steady. On the cue, turn your wrist RIGHT once. Hold the end position until asked to return.").font(.system(size:15)).foregroundStyle(muted)
                            }
                            Spacer()
                        }
                        if c.step == .calibrateLeft && !c.rightCalibrated {
                            Button("Repeat right swing") { c.step = .calibrateRight; c.calibrationPhase = "" }.buttonStyle(.borderedProminent)
                        }
                        Button((c.step == .calibrateRight ? c.rightCalibrated : c.calibrated) ? "Calibrate again" : "Begin calibration") { c.calibrate() }.buttonStyle(.borderedProminent).disabled(!c.streaming || c.calibrating || (c.step == .calibrateLeft && !c.rightCalibrated))
                        if c.calibrating { ProgressView(value:c.calibrationProgress).tint(accent) }
                        Text("Watch the guide, then begin. A two-second countdown gives you time to settle.").font(.system(size:12)).foregroundStyle(muted)
                    }
                case .practice:
                    VStack(alignment:.leading,spacing:13) {
                        HStack(spacing:12) {
                            practiceBadge("Right → next",done:c.practiceNext)
                            practiceBadge("Left → previous",done:c.practicePrev)
                            Spacer()
                            Toggle("Reverse directions",isOn:$c.reverseDirections).toggleStyle(.switch).font(.system(size:11))
                        }
                        Text(c.practiceMessage).font(.system(size:17,weight:.medium)).foregroundStyle(muted)
                        sensitivityRow
                    }
                case .ready:
                    VStack(alignment:.leading,spacing:14) {
                        Label("Both directions recognised",systemImage:"checkmark.seal.fill").font(.system(size:19,weight:.semibold)).foregroundStyle(.green)
                        Text("Open the deck on every viewing device. Enable presentation control when you’re ready. Pause it whenever you put the AirPod down.").font(.system(size:13)).foregroundStyle(muted)
                        Text("Your sensitivity and direction are saved. Restart setup anytime in the sidebar.").font(.system(size:12)).foregroundStyle(muted)
                    }
                }
            }.padding(22).frame(maxWidth:.infinity,alignment:.leading).frame(minHeight:200).background(panel,in:RoundedRectangle(cornerRadius:14))
            Spacer(minLength:0)
            HStack {
                if c.step != .connect { Button("Back") { c.back() }.disabled(c.calibrating) }
                else { Button("Use buttons for now") { c.setup = false; c.tab = "Control" } }
                Spacer()
                Text("\(c.step.rawValue+1) of 6").font(.system(size:11)).foregroundStyle(muted)
                Button(c.step == .ready ? "Finish setup" : "Continue") { c.advance() }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!c.canAdvance)
            }
        }
    }
    private var dashboard: some View {
        VStack(spacing:16) {
            stage(demo:false,height:280)
            VStack(spacing:0) {
                HStack {
                    VStack(alignment:.leading,spacing:5) {
                        Text("Presentation control").font(.system(size:15,weight:.semibold))
                        Text(c.controlHelp).font(.system(size:12)).foregroundStyle(muted)
                    }
                    Spacer()
                    Toggle("Presentation control",isOn:$c.enabled).labelsHidden().toggleStyle(.switch).disabled(!c.streaming || !c.calibrated)
                }.padding(20)
                Divider().overlay(.white.opacity(0.04)).padding(.horizontal,20)
                HStack(spacing:12) {
                    gestureButton("prev",title:"Previous",symbol:"arrow.left")
                    gestureButton("next",title:"Next",symbol:"arrow.right")
                }.controlSize(.large).padding(16)
            }.background(panel,in:RoundedRectangle(cornerRadius:14))
            HStack(spacing:12) {
                Image(systemName:"display.2").foregroundStyle(accent)
                VStack(alignment:.leading,spacing:4) {
                    Text(c.delivery).font(.system(size:12,weight:.medium))
                    Text(c.localRehearsal ? "Local rehearsal · this Mac" : c.relayURL == nil ? "Relay not configured · see Settings" : "Live presentation").font(.system(size:11)).foregroundStyle(c.relayURL == nil ? .orange : accent)
                    Text(c.streaming ? "Motion connected · \(c.side)" : c.status).font(.system(size:11)).foregroundStyle(muted)
                }
                Spacer()
                if !c.streaming {
                    Button("Retry motion") { c.retryMotion() }
                        .disabled(c.permission == .denied || c.permission == .restricted)
                }
                if let deck = c.relayURL { Button("Open deck") { NSWorkspace.shared.open(deck) }.buttonStyle(.borderless) }
            }.padding(.horizontal,4)
            if !c.calibrated { Button("Set up gesture control") { c.beginSetup(); c.step = .calibrateRight }.foregroundStyle(.orange) }
            Spacer(minLength:0)
        }
    }
    private var settings: some View {
        VStack(spacing:16) {
            stage(demo:false,height:245)
            Picker("Settings section",selection:$settingsTab) { Text("Gestures").tag("Gestures"); Text("Device & view").tag("Device"); Text("About").tag("About") }.pickerStyle(.segmented).labelsHidden()
            VStack(alignment:.leading,spacing:16) {
                if settingsTab == "Gestures" {
                    sensitivityRow
                    Divider()
                    HStack {
                        VStack(alignment:.leading,spacing:4) { Text("Time between gestures"); Text("A pause keeps the return swing from advancing twice.").font(.system(size:11)).foregroundStyle(muted) }
                        Spacer()
                        Slider(value:$c.cooldown,in:0.8...2.5).frame(width:190)
                        Text(String(format:"%.1f s",c.cooldown)).monospacedDigit().frame(width:40)
                    }.font(.system(size:12))
                    Divider()
                    HStack { Text("Reverse left and right"); Spacer(); Toggle("Reverse left and right",isOn:$c.reverseDirections).labelsHidden().toggleStyle(.switch) }.font(.system(size:12))
                } else if settingsTab == "Device" {
                    HStack { Toggle("Local rehearsal on this Mac",isOn:$c.localRehearsal).toggleStyle(.switch); Spacer(); Text(c.relayURL?.absoluteString ?? "Relay not configured").font(.system(size:11)).foregroundStyle(c.relayURL == nil ? .orange : muted) }
                    Text("Gestures go to REMOTE_URL using REMOTE_TOKEN from \(c.configPath). Changing this pauses presentation control.").font(.system(size:11)).foregroundStyle(muted)
                    Divider()
                    HStack { Text("Motion source"); Spacer(); Text(c.side).foregroundStyle(muted) }.font(.system(size:12))
                    Divider()
                    HStack { Text("Show hand in movement guides"); Spacer(); Toggle("Show hand in movement guides",isOn:$c.showHand).labelsHidden().toggleStyle(.switch) }.font(.system(size:12))
                    HStack { Button(c.monitoring ? "Restart motion" : "Start motion") { c.stop(); c.start() }; Button("Set neutral pose") { c.recenter() }; Spacer() }
                    Text("Hold the AirPod upright and choose Set neutral pose. The view shows rotation from that pose, not location in space. The hand appears only in demonstrations.").font(.system(size:11)).foregroundStyle(muted)
                } else {
                    Text("Designed for the moment.").font(.system(size:19,weight:.semibold))
                    Text("AirSlide · open source under the MIT licence\nNative motion, one presenter, every screen.").font(.system(size:12)).foregroundStyle(muted)
                    Link("github.com/Tarabcak/airslide",destination:URL(string:"https://github.com/Tarabcak/airslide")!).font(.system(size:11))
                    Link("AirPods Pro model by JY_JY_ · CC BY 4.0",destination:URL(string:"https://sketchfab.com/3d-models/airpods-pro-4478dddbfa244f6f9b93eebbd027a73b")!).font(.system(size:11))
                    Text("Model adapted: case removed, earbuds separated and reoriented, simplified materials. Visual reference, not exact Pro 3 CAD. Hand mesh adapted from Immersive Web input profiles (MIT).").font(.system(size:11)).foregroundStyle(muted)
                    Link("Creative Commons Attribution 4.0",destination:URL(string:"https://creativecommons.org/licenses/by/4.0/")!).font(.system(size:11))
                }
            }.padding(20).frame(maxWidth:.infinity,alignment:.leading).background(panel,in:RoundedRectangle(cornerRadius:14))
            HStack { Text("Changes save automatically.").font(.system(size:11)).foregroundStyle(muted); Spacer(); Button("Recalibrate…") { c.beginSetup(); c.step = .calibrateRight } }
            Spacer(minLength:0)
        }
    }
    private var sensitivityRow: some View {
        HStack(spacing:24) {
            VStack(alignment:.leading,spacing:5) {
                Text("Gesture sensitivity").font(.system(size:12,weight:.medium))
                Text("Choose how deliberate a swing should feel.").font(.system(size:11)).foregroundStyle(muted)
            }
            Spacer(minLength:0)
            VStack(spacing:4) {
                Slider(value:Binding(get:{c.sensitivity},set:{c.sensitivity=$0}),in:0.6...6)
                HStack { Text("Deliberate"); Spacer(); Text("Light") }.font(.system(size:10)).foregroundStyle(muted)
            }.frame(width:260)
        }
    }
    private func gestureButton(_ direction:String,title:String,symbol:String) -> some View {
        Button { c.send(direction) } label: {
            Label(title,systemImage:symbol).frame(maxWidth:.infinity).padding(.vertical,10)
                .foregroundStyle(pulseDirection == direction ? .green : .primary)
                .background(pulseDirection == direction ? Color.green.opacity(0.20) : Color.white.opacity(0.06),in:Capsule())
                .overlay(Capsule().stroke(pulseDirection == direction ? Color.green.opacity(0.7) : Color.clear,lineWidth:1))
        }.buttonStyle(.plain)
    }
    private func connectionRow(_ symbol:String,_ title:String,_ detail:String,_ state:String,complete:Bool,pending:Bool) -> some View {
        HStack(alignment:.top,spacing:14) {
            Image(systemName:symbol).font(.system(size:17,weight:.medium)).foregroundStyle(complete ? .green : accent)
                .frame(width:30,height:30).background((complete ? Color.green : accent).opacity(0.10),in:RoundedRectangle(cornerRadius:8))
            VStack(alignment:.leading,spacing:7) {
                HStack(alignment:.firstTextBaseline) {
                    Text(title).font(.system(size:16,weight:.semibold))
                    Spacer(minLength:12)
                    Label(state,systemImage:complete ? "checkmark.circle.fill" : pending ? "circle.dotted" : "exclamationmark.circle.fill")
                        .font(.system(size:11,weight:.medium)).foregroundStyle(complete ? .green : pending ? muted : .orange)
                }
                Text(detail).font(.system(size:13)).lineSpacing(3).foregroundStyle(muted).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
    private func instruction(_ symbol:String,_ title:String,_ text:String) -> some View {
        HStack(alignment:.top,spacing:14) {
            Image(systemName:symbol).font(.system(size:17,weight:.medium)).foregroundStyle(accent)
                .frame(width:30,height:30).background(accent.opacity(0.10),in:RoundedRectangle(cornerRadius:8))
            VStack(alignment:.leading,spacing:6) {
                Text(title).font(.system(size:16,weight:.semibold)).foregroundStyle(.white.opacity(0.95))
                Text(text).font(.system(size:14)).lineSpacing(3).foregroundStyle(muted)
                    .fixedSize(horizontal:false,vertical:true).frame(maxWidth:530,alignment:.leading)
            }
            Spacer(minLength:0)
        }
    }
    private func practiceBadge(_ text:String,done:Bool) -> some View {
        Label(text,systemImage:done ? "checkmark.circle.fill" : "circle.dashed").font(.system(size:14,weight:.medium)).foregroundStyle(done ? .green : muted).padding(9).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:8))
    }
    private func openSettings(_ url:String) { if let url = URL(string:url) { NSWorkspace.shared.open(url) } }
}
