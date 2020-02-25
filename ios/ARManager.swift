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
@objc public class ARManager : NSObject {
    
    var _loadedScenes: [String: Entity] = [:];
    let _configuration = ARWorldTrackingConfiguration();
    var _webview: RNCWebView? = nil;
    
    var _hasItem = false;
    
    var _arview = ARView(frame: CGRect());
    
    var _center_x = CGFloat(0);
    var _center_y = CGFloat(0);
    
    // MARK: Public Objective-C API
    
    // Method to link with our WebView
    @objc public func attach(webview: RNCWebView, toFrame:CGRect) {
        print("Attaching AR from Swift...");
        
        URLCache.shared = URLCache(memoryCapacity: 100 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024);
        
        self._arview.frame = toFrame;
        self._webview = webview;
        
        _configuration.isAutoFocusEnabled = false;
        _configuration.planeDetection = .horizontal;
//        self._arview?.session.run(_configuration);
    }
    
    @objc public func view() -> UIView {
        return self._arview;
    }
    
    @objc public func pause() {
        print("Pausing Swift setup");
//        self._arview.session.pause();
    }
    
    // Public method to recieve messages from WebView
    @objc public func notify(message: [String:Any]){
        print("Got Swift message \(message)");
        
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
        print("Setting up coaching overlay...")
    }
    
    func placeLoadedObject(_ name: String, withOptions: [String:Any]){
        print("Placing loaded object: \(name)");
    }
    
    func playAllAnimations(withRepeat: Bool){
        print("Playing animations withRepeat \(withRepeat)");
    }
    
    // MARK: Private Instance Methods
    func addAnimationEvents(onNode: Entity, forName: String){
        print("Preparing animation events for node \(forName)");
    }
    
    func sendMessage(_ data: [String: Any]){
        guard let webview = self._webview else { return; }
        webview.sendScriptMessage(data);
    }
}

// MARK: Helper Methods

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
            print("Returning cached file url: \(cachedFileUrl!)");
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
