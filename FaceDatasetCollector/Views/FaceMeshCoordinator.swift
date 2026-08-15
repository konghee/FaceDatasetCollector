//
//  FaceMeshCoordinator.swift
//  FaceDatasetCollector
//
//  Created by jeonghee on 8/15/26.
//

import SwiftUI
import ARKit
import SceneKit

class Coordinator: NSObject, ARSCNViewDelegate {
    
    func renderer(
        _ renderer: SCNSceneRenderer,
        nodeFor anchor: ARAnchor
    ) -> SCNNode? {
        guard
            anchor is ARFaceAnchor,
            let sceneView = renderer as? ARSCNView,
            let device = sceneView.device,
            let geometry = ARSCNFaceGeometry(device: device, fillMesh: true)
        else { return nil }
        
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.systemCyan
        material.emission.contents = UIColor.systemCyan.withAlphaComponent(0.35)
        material.fillMode = .lines
        material.isDoubleSided = true
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }
    
    func renderer(
        _ renderer: SCNSceneRenderer,
        didUpdate node: SCNNode,
        for anchor: ARAnchor
    ) {
        guard
            let faceAnchor = anchor as? ARFaceAnchor,
            let faceGeometry = node.geometry as? ARSCNFaceGeometry
        else { return }
        
        faceGeometry.update(from: faceAnchor.geometry)
        
    }
}
