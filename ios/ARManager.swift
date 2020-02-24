//
//  ARManager.swift
//  RNCWebView
//
//  Created by Peter Andringa on 2/23/20.
//  Copyright © 2020 Facebook. All rights reserved.
//

import Foundation

#if canImport(RealityKit)
import RealityKit

@available(iOS 13.0, *)
@objc public class ARManager : NSObject {

    var _urlCache = URLCache(memoryCapacity: 100 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024);
    
    var _loadedScenes: [String: ARView] = [:];
    
    @objc public func start() {
        print("Running AR from Swift...");
        URLCache.shared = _urlCache;
        
    }
}

#endif