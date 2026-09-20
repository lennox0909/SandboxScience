//
//  ContentView.swift
//  SandboxScience
//
//  Created by Tsai Bing-Shi on 2026/9/20.
//

import SwiftUI
import RealityKit

struct ContentView: View {

    var body: some View {
        VStack {
            Model3D(named: "Scene", bundle: .main)
                .padding(.bottom, 50)

            Text("Hello, world!")

            ToggleImmersiveSpaceButton()
        }
        .padding()
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
