import SwiftUI
import SceneKit
import simd

private struct MeshPart: Decodable {
    let positions: Data
    let normals: Data
    let indices: Data
    let material: Int
}

struct MotionScene: NSViewRepresentable {
    var orientation: simd_quatf
    var side: String
    var demonstration: Bool
    var showHand: Bool
    var connected: Bool
    var guideDirection: Int = 1
    var showGuide: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    final class Coordinator {
        var model = SCNNode()
        var hand = SCNNode()
        var group = SCNNode()
        var side = ""
        var demonstrating = false
        var guide = SCNNode()
        var direction = 0
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        view.scene = scene; view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X; view.preferredFramesPerSecond = 30
        view.autoenablesDefaultLighting = false; view.allowsCameraControl = false
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true; camera.camera?.orthographicScale = 2.8
        camera.position = SCNVector3(0,0,9); scene.rootNode.addChildNode(camera); view.pointOfView = camera
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 180; ambient.light?.color = NSColor(white:0.95,alpha:1)
        scene.rootNode.addChildNode(ambient)
        for (position,intensity) in [(SCNVector3(-3,5,6),CGFloat(450)),(SCNVector3(4,1,-2),CGFloat(300))] {
            let light = SCNNode(); light.light = SCNLight(); light.light?.type = .omni; light.light?.intensity = intensity
            light.position = position; scene.rootNode.addChildNode(light)
        }
        context.coordinator.group.position = SCNVector3(0,0.45,0)
        scene.rootNode.addChildNode(context.coordinator.group)
        context.coordinator.hand = Self.makeEarbud("hand")
        context.coordinator.guide = Self.makeGuide()
        scene.rootNode.addChildNode(context.coordinator.guide)
        context.coordinator.group.addChildNode(context.coordinator.hand)
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: SCNView, context: Context) {
        let c = context.coordinator
        let selected = side == "Left AirPod" ? "left" : "right"
        if c.side != selected {
            c.model.removeFromParentNode(); c.model = Self.makeEarbud(selected)
            c.model.scale = SCNVector3(0.6,0.6,0.6)
            c.model.position = SCNVector3(0.50,0.40,0.55)
            c.model.eulerAngles = SCNVector3(0.14, selected == "left" ? -0.55 : 0.55,0)
            c.group.addChildNode(c.model); c.side = selected
        }
        // A live orientation rotates about the earbud itself, not a decorative hand pivot.
        c.model.scale = demonstration ? SCNVector3(0.6,0.6,0.6) : SCNVector3(1,1,1)
        c.model.position = demonstration ? SCNVector3(0.50,0.40,0.55) : SCNVector3(0,0,0)
        c.model.eulerAngles = demonstration ? SCNVector3(0.14, selected == "left" ? -0.55 : 0.55,0) : SCNVector3(0,0,0)
        c.hand.isHidden = !showHand || !demonstration
        c.guide.isHidden = !showGuide
        c.guide.scale.x = guideDirection < 0 ? -1 : 1
        let animate = demonstration && !reduceMotion
        if animate != c.demonstrating || guideDirection != c.direction {
            c.direction = guideDirection
            c.group.removeAllActions(); c.demonstrating = animate
            if animate {
                c.group.simdOrientation = simd_quatf(angle:0,axis:[0,0,1])
                let swing = SCNAction.rotateTo(x:0,y:0.15,z:CGFloat(guideDirection) * -0.65,duration:0.7); swing.timingMode = .easeInEaseOut
                let rest = SCNAction.rotateTo(x:0,y:0,z:0,duration:1.1); rest.timingMode = .easeInEaseOut
                c.group.runAction(.repeatForever(.sequence([.wait(duration:1),swing,.wait(duration:0.4),rest,.wait(duration:0.7)])))
            }
        }
        if !animate {
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0
            SCNTransaction.disableActions = true
            c.group.simdOrientation = connected && !demonstration ? orientation : simd_quatf(angle:0,axis:[0,1,0])
            SCNTransaction.commit()
        }
    }
    static func makeEarbud(_ side: String) -> SCNNode {
        let node = SCNNode()
        guard let url = Bundle.main.url(forResource:side,withExtension:"json"),
              let data = try? Data(contentsOf:url), let parts = try? JSONDecoder().decode([MeshPart].self,from:data) else { return node }
        for part in parts {
            let vertices = SCNGeometrySource(data:part.positions,semantic:.vertex,vectorCount:part.positions.count/12,usesFloatComponents:true,componentsPerVector:3,bytesPerComponent:4,dataOffset:0,dataStride:12)
            let normals = SCNGeometrySource(data:part.normals,semantic:.normal,vectorCount:part.normals.count/12,usesFloatComponents:true,componentsPerVector:3,bytesPerComponent:4,dataOffset:0,dataStride:12)
            let indices = SCNGeometryElement(data:part.indices,primitiveType:.triangles,primitiveCount:part.indices.count/12,bytesPerIndex:4)
            let geometry = SCNGeometry(sources:[vertices,normals],elements:[indices])
            let material = SCNMaterial(); material.lightingModel = .physicallyBased
            material.diffuse.contents = [0,3].contains(part.material) ? NSColor(white:0.055,alpha:1) : NSColor(white:part.material == 1 ? 0.72 : 0.82,alpha:1)
            if part.material == 5 { material.diffuse.contents = NSColor(red:0.69,green:0.57,blue:0.46,alpha:1) }
            material.roughness.contents = part.material == 1 ? 0.7 : 0.24
            material.metalness.contents = part.material == 4 ? 0.7 : 0.0
            if part.material == 5 { material.roughness.contents = 0.85 }
            material.isDoubleSided = true; geometry.materials = [material]
            node.addChildNode(SCNNode(geometry:geometry))
        }
        return node
    }
    static func makeGuide() -> SCNNode {
        let guide = SCNNode()
        let material = SCNMaterial(); material.lightingModel = .physicallyBased
        material.diffuse.contents = NSColor(red:0.64,green:0.88,blue:0.75,alpha:1)
        material.emission.contents = NSColor(red:0.08,green:0.22,blue:0.14,alpha:1)
        material.roughness.contents = 0.32
        func point(_ t: Float) -> SIMD3<Float> {
            [2.0 * sin(t), 1.1 + 0.8 * cos(t), 1.1 * cos(t)]
        }
        for i in 0..<48 {
            let a = point(-1.1 + Float(i) * 2.2 / 48)
            let b = point(-1.1 + Float(i+1) * 2.2 / 48)
            let delta = b-a
            let node = SCNNode(geometry:SCNCylinder(radius:0.04,height:CGFloat(simd_length(delta)) + 0.005))
            node.geometry?.materials = [material]; node.simdPosition = (a+b)*0.5
            node.simdOrientation = simd_quatf(from:SIMD3<Float>(0,1,0),to:simd_normalize(delta))
            guide.addChildNode(node)
        }
        let head = SCNNode(geometry:SCNCone(topRadius:0,bottomRadius:0.12,height:0.32))
        head.geometry?.materials = [material]; head.simdPosition = point(1.14)
        head.simdOrientation = simd_quatf(from:SIMD3<Float>(0,1,0),to:simd_normalize(point(1.15)-point(1.10)))
        guide.addChildNode(head)
        // Upright ticks make the path's depth and end position visible from the fixed camera.
        for t: Float in [-1.1, 0, 1.1] {
            let tick = SCNNode(geometry:SCNSphere(radius:0.065))
            tick.geometry?.materials = [material]; tick.simdPosition = point(t)
            guide.addChildNode(tick)
        }
        return guide
    }
}
