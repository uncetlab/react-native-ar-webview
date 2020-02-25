//
//  ARManager.swift
//  RNCWebView
//
//  Created by Peter Andringa on 2/23/20.
//  Copyright © 2020 Facebook. All rights reserved.
//

import Foundation;
import UIKit;
import RealityKit;

// Tag print statements with [SWIFT]
func print(_ str: String) {
    print("[SWIFT]", str);
}

@available(iOS 13.0, *)
@objc public class ARManager : UIView, ARCoachingOverlayViewDelegate, ARSessionDelegate {
    
    var _loadedScenes: [String: Entity] = [:];
    let _configuration = ARWorldTrackingConfiguration();
    var _webview: RNCWebView? = nil;
        
    var _arview = ARView(frame: CGRect());
    
    var _center_x = CGFloat(0);
    var _center_y = CGFloat(0);
    
    var _sceneReady = false;
    var _hasItem = false;
    var _placeMarker: ModelEntity? = nil;
    var _markerPos: simd_float4? = nil;
    var _camAngle: Float = 0.0;
    
    // MARK: Public Objective-C API
    
    // Method to link with our WebView
    @objc public func attach(webview: RNCWebView) {
        print("Attaching AR from Swift...");
        
        URLCache.shared = URLCache(memoryCapacity: 100 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024);
        
        self._webview = webview;
        
        // layout arview
        self._arview.frame = self.frame;
        self._arview.translatesAutoresizingMaskIntoConstraints = false;
        self.addSubview(_arview);
        _arview.topAnchor.constraint(equalTo: self.topAnchor).isActive = true;
        _arview.leftAnchor.constraint(equalTo: self.leftAnchor).isActive = true;
        _arview.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true;
        _arview.rightAnchor.constraint(equalTo: self.rightAnchor).isActive = true;
        
        // start ar camera + rendering
        _configuration.isAutoFocusEnabled = false;
        _configuration.planeDetection = .horizontal;
        self._arview.session.delegate = self;
        self._arview.session.run(_configuration);
    }
    
    @objc public func pause() {
        print("Pausing Swift setup");
        self._arview.session.pause();
    }
    
    // Public method to recieve messages from WebView
    @objc public func notify(message: [String:Any]){
        
        guard let data: [String:Any] = message["data"] as? [String : Any] else {
            print("Error: no data object included in message \(message)");
            return
        }
        
        guard let action: String = data["action"] as? String else {
            print("Error: every message must have an action. Data is: \(data)");
            return
        }
        
        switch action {
        case "init":
            guard let assets: [String: [String:Any]] = data["assets"] as? [String: [String:Any]] else {
                print("Erorr: Init requires a dictionary of asset names -> {}");
                return;
            }
            
            self._center_x = _arview.bounds.origin.x + _arview.bounds.size.width/2.0;
            self._center_y = _arview.bounds.origin.y + _arview.bounds.size.height/2.0;
            print("Running init with xy (\(_center_x), \(_center_y))");
            
            for (name, asset_data) in assets {
                guard let url_str = asset_data["url"] as? String,
                    let url = URL(string: url_str) else {
                        print("Error: missing or malformed URL for asset '\(name)': \(asset_data)");
                        return;
                }
                self.initAsset(fromUrl: url, forName: name, withOptions:asset_data);
            }
            
            if (data["coachingOverlay"] != nil) {
                self.setupCoachingOverlay();
            }
        case "place":
            guard let asset: String = data["asset"] as? String else {
                print("Error: Asset name is required for 'place' actions. Data was: \(data)");
                return;
            }
            NSLog("Attempting to place object \(asset)");
            
            self.placeLoadedObject(asset, withOptions: data);
        case "play":
            self.playAllAnimations(withRepeat: (data["loop"] != nil));
        default:
            print("Error: Unrecognized action '\(action)'");
        }
    }
    
    // MARK: Private Lifecycle Methods
    func initAsset(fromUrl url:URL, forName:String, withOptions:[String:Any]){
        guard (_loadedScenes[forName] == nil) else {
            print("Error: Scene \(forName) already exists.");
            sendMessage([
                "event": "loaded",
                "asset": forName
            ]);
            return;
        }
        
        downloadAsset(url, onComplete: {(location: URL) in
            print("Setting up scene entity...");
            
            // TK Load URL into Scene
            let newEntity = Entity();
            
            self.addAnimationEvents(onNode:newEntity, forName:forName);
            
            self._loadedScenes[forName] = newEntity;
            
            print("Loaded scene \(forName)");
            self.sendMessage([
                "event": "loaded",
                "asset": forName
            ]);
        });
    }
    
    func setupCoachingOverlay(){
        print("Setting up coaching overlay...");
        let overlay = ARCoachingOverlayView(frame: self.frame);
        overlay.delegate = self;
        overlay.session = self._arview.session;
        overlay.activatesAutomatically = true;
        overlay.goal = .horizontalPlane;
        
        self.addSubview(overlay);
    }
    
    func placeLoadedObject(_ name: String, withOptions: [String:Any]){
        print("Placing loaded object: \(name)");
    }
    
    func playAllAnimations(withRepeat: Bool){
        print("Playing animations withRepeat \(withRepeat)");
    }
    
    // MARK: - Coaching Overlay Delegate
    
    public func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
        print("Coaching overlay view active");
        self._sceneReady = false;
        self._hasItem = false;
        self.sendMessage(["event": "overlayShown"]);
    }
    
    public func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
        print("Coaching overlay view deactivated");
        self._sceneReady = true;
        self.sendMessage(["event": "overlayHidden"]);
    }
    
    public func coachingOverlayViewDidRequestSessionReset(_ coachingOverlayView: ARCoachingOverlayView) {
        print("User wants to reset coaching overlay view");
        self._sceneReady = false;
        self.sendMessage(["event": "overlayReset"]);
    }
    
    // MARK: ARSessionObserver

    public func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        print("Found \(anchors.count) anchors.")
        
        // Add non-existing anchors to scene
        let currentIds = _arview.scene.anchors.map{ $0.anchorIdentifier }
        for anchor in anchors where !currentIds.contains(anchor.identifier){
            _arview.scene.addAnchor(AnchorEntity(anchor: anchor));
        }
        
        if(_placeMarker != nil) {
            self.updateRaycastPoint();
        }else if(!_hasItem){
            self.setupRaycastPoint();
        }
    }
    
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if(_placeMarker != nil){
            self.updateRaycastPoint();
        }
    }
    
    public func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        print("Removing \(anchors.count) anchors.");
        
        // Remove anchors from scene too
        let currentIds = _arview.scene.anchors.map{ $0.anchorIdentifier }
        for anchor in anchors {
            if let i = currentIds.firstIndex(of: anchor.identifier) {
                _arview.scene.removeAnchor(_arview.scene.anchors[i]);
            }
        }
    }
    
    public func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        if case .normal = camera.trackingState {
            self.sendMessage(["event": "tracking"]);
        }
    }
    
    public func sessionWasInterrupted(_ session: ARSession) {
        print("AR session was interrupted.");
        self.sendMessage(["event": "interrupted"]);
    }
    
    public func sessionInterruptionEnded(_ session: ARSession) {
        print("AR session interruption ended.");
        self.sendMessage(["event": "interruptionEnded"]);
    }
    
    public func session(_ session: ARSession, didFailWithError error: Error) {
        print("AR session failed with error");
        self.sendMessage(["event": "error", "message": "\(error)"]);
    }
    
    // MARK: Private Instance Methods
    func setupRaycastPoint(){
        print("Attempting to set up raycast point.");
        print("Scene anchors so far: \(_arview.scene.anchors.count)");
        
        let shadowMesh = MeshResource.generatePlane(width: 0.5, depth: 0.5, cornerRadius: 0.5);
        let shadowMat = UnlitMaterial(color: UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.85));
        
        _placeMarker = ModelEntity(mesh: shadowMesh, materials: [shadowMat]);
        
        self.updateRaycastPoint();
        _arview.scene.anchors[_arview.scene.anchors.count - 1].addChild(_placeMarker!);
        self._sceneReady = true;
        
        self.sendMessage(["event": "plane"]);
    }
    func updateRaycastPoint(){
        guard let shadow = _placeMarker else { return; }
        
        let hits = self._arview.raycast(from: CGPoint(x: _center_x,y: _center_y), allowing: .existingPlaneGeometry, alignment: .horizontal);
        
        if(hits.count > 0) {
            _markerPos = hits[0].worldTransform.columns.3;
            _camAngle = self._arview.session.currentFrame!.camera.eulerAngles[1]
            shadow.setPosition(SIMD3(_markerPos!.x, _markerPos!.y, _markerPos!.z), relativeTo: nil);
        }
    }
    
    func addAnimationEvents(onNode: Entity, forName: String){
        print("Preparing animation events for node \(forName)");
    }
    
    func sendMessage(_ data: [String: Any]){
        guard let webview = self._webview else { return; }
        webview.sendScriptMessage(data);
    }
}

// MARK: - Helper Methods

// Returns the local folder for a remote URL
func getCacheFolder(url: URL) -> URL? {
    let pathStem = url.deletingLastPathComponent().path;
    return URL(fileURLWithPath: "\(NSHomeDirectory())/Library/SwiftCaches/\(url.host ?? "local")\(pathStem)");
}

// Returns the filename inside the cache folder
func getCacheFile(url: URL, etag: String) -> String {
    let cleanEtag = etag.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "/", with: "_");
    return "\(cleanEtag)-\(url.lastPathComponent)";
}

// Checks the cache for a given URL
func checkCache(url: URL) -> URL? {
    guard let cacheFolder = getCacheFolder(url: url),
        let dirFiles = FileManager.default.enumerator(atPath: cacheFolder.path) else {
        print("Corrupted or missing cache in checkCache \(url)");
        return nil;
    };
    
    for case let file as String in dirFiles {
        
        // Check matches against our filename component
        if(file.hasSuffix(url.lastPathComponent)){
            return cacheFolder.appendingPathComponent(file);
        }
    }
    
    return nil;
}

func downloadAsset(_ remoteUrl: URL, onComplete: @escaping (URL) -> Void) {
    var cachedEtag: String? = nil;
    let cachedFileUrl = checkCache(url: remoteUrl);
    if(cachedFileUrl != nil)  {
        cachedEtag = cachedFileUrl?.lastPathComponent.components(separatedBy: "-")[0];
    }
    
    var downloadRequest = URLRequest(url: remoteUrl);
    if let tag = cachedEtag {
        downloadRequest.addValue("\"\(tag)\"", forHTTPHeaderField: "If-None-Match");
    }
    
    let downloadTask = URLSession.shared.downloadTask(with: downloadRequest, completionHandler: { (location: URL?, response: URLResponse?, error: Error?) in
        
        // Strange file download errors
        guard let tempFilePath = location,
            let httpResponse = response as? HTTPURLResponse,
            (error == nil) else {
            print("Error: file download failed. \(error!)");
            return;
        }
        
        // Server isn't configured for etag (never AWS)
        guard let etag = httpResponse.value(forHTTPHeaderField: "ETag") else {
            print("Error: No ETag among response headers \(httpResponse.allHeaderFields)");
            return;
        }
        
        // Server matches ours, so just return ours.
        if(httpResponse.statusCode == 304) {
            print("Returning cached file url: \(cachedFileUrl!.lastPathComponent)");
            return onComplete(cachedFileUrl!);
        }
        
        // Server returns another non-200 status code
        guard (httpResponse.statusCode == 200) else {
            print("Error: non-200 response for URL \(remoteUrl)");
            return
        }
        
        // We probably need to delete the old, out-of-date file
        if(cachedEtag != nil && cachedEtag != etag) {
            do {
                try FileManager.default.removeItem(atPath: cachedFileUrl!.path)
            } catch {
                print("Error removing expired file at path \(cachedFileUrl!.path): \(error)");
            }
        }
        
        let cacheFolder: URL = getCacheFolder(url: remoteUrl)!;
        do {
            try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Error creating directories for \(cacheFolder) \(error)");
        }
        
        let cacheSaveUrl = cacheFolder.appendingPathComponent(getCacheFile(url: remoteUrl, etag: etag));
        
        // Replace the old file
        if(FileManager.default.fileExists(atPath: cacheSaveUrl.path)) {
            do {
                try FileManager.default.removeItem(atPath: cachedFileUrl!.path)
            } catch {
                print("Error replacing existing file in cache \(cachedFileUrl!.path): \(error)");
                return;
            }
        }
        
        do {
            try FileManager.default.moveItem(at: tempFilePath, to: cacheSaveUrl);
        } catch {
            print("Error moving file out of temp directory: \(error)");
        }
        
        print("Loaded file from url: \(remoteUrl). Placed in file \(cacheSaveUrl)");
        onComplete(cacheSaveUrl);
    });
    
    downloadTask.resume();
}
