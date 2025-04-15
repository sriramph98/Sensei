//
//  SenseiApp.swift
//  Sensei
//
//  Created by Sriram P H on 4/15/25.
//

import SwiftUI

@main
struct SenseiApp: App {
    var body: some Scene {
        WindowGroup {
            DepthCameraView()
        }
    }
}

struct DepthCameraView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DepthCameraViewController {
        return DepthCameraViewController()
    }
    
    func updateUIViewController(_ uiViewController: DepthCameraViewController, context: Context) {
        // Update the view controller if needed
    }
}
