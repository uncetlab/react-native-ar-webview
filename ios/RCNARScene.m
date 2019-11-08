//
//  RCNARScene.m
//  RNCWebView
//
//  Created by Peter Andringa on 10/28/19.
//  Copyright © 2019 Facebook. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <ARKit/ARKit.h>
#import <SceneKit/SceneKit.h>
#import <SceneKit/ModelIO.h>

#import "RCNARScene.h"


@implementation RCNARScene

bool _sceneSet = NO;
ARPlaneAnchor *_planeAnchor;
SCNScene *_loadedScene;

- (void)setup
{
    if(_sceneSet){
        return;
    }
    
    // Enable NSUrl caching
    NSURLCache *URLCache = [[NSURLCache alloc] initWithMemoryCapacity: 25 * 1024 * 1024 // 25mb (~1 model)
                                                         diskCapacity: 100 * 1024 * 1024 // 100mb (~4 models)
                                                             diskPath:nil];
    [NSURLCache setSharedURLCache:URLCache];
    
    self.delegate = self;
    self.debugOptions = ARSCNDebugOptionShowFeaturePoints;
    self.autoenablesDefaultLighting = YES;
    self.automaticallyUpdatesLighting = YES;
    
    SCNScene *scene = [SCNScene new];
    self.scene = scene;
    
//    let cubeNode = SCNNode(geometry: SCNBox(width: 0.1, height: 0.1, length: 0.1, chamferRadius: 0))
//    cubeNode.position = SCNVector3(0, 0, -0.2) // SceneKit/AR coordinates are in meters
//    sceneView.scene.rootNode.addChildNode(cubeNode)

    ARWorldTrackingConfiguration *configuration = [ARWorldTrackingConfiguration new];
    configuration.planeDetection = ARPlaneDetectionHorizontal;
    
    [self.session runWithConfiguration:configuration];
    _sceneSet = YES;
}

- (void)initSceneFromUrl:(NSURL*) url {
    [[self class] downloadAssetURL:url completionHandler:^(NSURL* location) {
        NSError *sceneError = nil;
        _loadedScene = [SCNScene sceneWithURL:location options:nil error:&sceneError];
        // [self placeLoadedSceneObjects];
        
        if(_planeAnchor){
            [self sendMessage:@{
              @"event": @"plane"
            }];
        }
        
        if(sceneError){
            NSLog(@"Scene error!!! %@", sceneError);
        }
    }];
}

- (void)placeLoadedSceneObjects {
    if(_loadedScene && _planeAnchor){
        NSLog(@"Placing objects...");
        for(SCNNode *node in _loadedScene.rootNode.childNodes){
            node.simdPosition = _planeAnchor.center;
            node.simdTransform = _planeAnchor.transform;
            node.scale = SCNVector3Make(0.01, 0.01, 0.01);
            [self.scene.rootNode addChildNode:node];
        }
        
        [self sendMessage:@{
          @"event": @"rendered",
          @"extra": @"data",
          @"statusCode": @200
        }];
        
    }else{
        if(_planeAnchor)
            NSLog(@"Have anchor, waiting for scene...");
        else if(_loadedScene)
            NSLog(@"Have scene, waiting for anchor...");
        else
            NSLog(@"Waiting for scene and anchor");
    }
}
    
- (void)sendMessage:(NSDictionary<NSString *, id>*)message {
    [self.webview sendScriptMessage:message];
}

- (void)onMessage:( NSMutableDictionary<NSString *, id>* )message {
    if(![message objectForKey:@"data"] || ![message[@"data"] isKindOfClass:[NSDictionary class]]){
       NSLog(@"Error: no data object included in message %@", message);
       return;
    }
    
    NSDictionary *data = message[@"data"];
    if(![data objectForKey:@"action"]){
        NSLog(@"Error: no action included page in data %@", data);
        return;
    }
    
    NSString *action = message[@"data"][@"action"];
    if([action isEqualToString:@"init"]){
        NSString *urlStr = message[@"data"][@"url"];
        if(!urlStr){
            NSLog(@"Error: Action is init, but no URL was provided.");
            return;
        }
        
        NSURL *url = [NSURL URLWithString:urlStr];
        if(!url){
            NSLog(@"Error: Malformed URL for '%@' action: %@ ", action, urlStr);
            return;
        }
        
        [self initSceneFromUrl:url];
    }else if([action isEqualToString:@"place"]){
        NSLog(@"Attempting to place object...");
        [self placeLoadedSceneObjects];
    }else{
        NSLog(@"Error: Unrecognized action: %@", action);
    }
}

/**
 * SceneKit delegate methods
**/
- (void)renderer:(id<SCNSceneRenderer>)renderer didAddNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor  API_AVAILABLE(ios(11.0)){
    NSLog(@"Adding node! %@", anchor);
    if (_planeAnchor || ![anchor isKindOfClass:[ARPlaneAnchor class]]) {
      return;
    }
    ARPlaneAnchor *plane = (ARPlaneAnchor*)anchor;
    _planeAnchor = plane;
    
//    SCNPlane *planeGeometry = [SCNPlane planeWithWidth:plane.extent.x height:plane.extent.z];
//    planeGeometry.materials.firstObject.diffuse.contents = [UIColor  colorWithRed:0.2 green:0.2 blue:0.2 alpha:1];
//    
//    SCNNode *planeNode = [SCNNode nodeWithGeometry:planeGeometry];
//    planeNode.opacity = 0.75;
//    // Move the plane to the position reported by ARKit
//    planeNode.simdPosition = plane.center;
//    planeNode.simdTransform = plane.transform;
//    // Planes in SceneKit are vertical by default so we need to rotate
//    // 90 degrees to match planes in ARKit
//    planeNode.eulerAngles = SCNVector3Make(-M_PI_2, 0.0, 0.0);
//    
//    [self.scene.rootNode addChildNode:planeNode];
    
//    [self placeLoadedSceneObjects];
    if(_loadedScene){
        [self sendMessage:@{
          @"event": @"plane"
        }];
    }
}

- (void)renderer:(id<SCNSceneRenderer>)renderer didRemoveNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor  API_AVAILABLE(ios(11.0)){
    NSLog(@"Removed node! %@", node);
    NSLog(@"On anchor: %@", anchor);
}


/**
* Helpers
**/

+ (void)downloadAssetURL:(NSURL*)remoteUrl completionHandler:(void(^)(NSURL*))handler {
    NSURL *cachedFileUrl = [[self class] checkCacheForURL:remoteUrl];
    NSString* cachedEtag = nil;
    if(cachedFileUrl){
        NSString* cachedFileName =[cachedFileUrl lastPathComponent];
        cachedEtag = [cachedFileName componentsSeparatedByString:@"-"][0];
    }
    
    NSMutableURLRequest *downloadRequest = [NSMutableURLRequest requestWithURL:remoteUrl];
    if(cachedEtag){
        [downloadRequest setValue:[NSString stringWithFormat:@"\"%@\"", cachedEtag] forHTTPHeaderField:@"If-None-Match"];
    }
    
    NSURLSessionDownloadTask *downloadTask = [[NSURLSession sharedSession] downloadTaskWithRequest:downloadRequest completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if(error){
            NSLog(@"Error: File download error: %@", error);
            return;
        }
        
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSDictionary *headers = httpResponse.allHeaderFields;
        if(![headers objectForKey:@"ETag"]){
            NSLog(@"No ETag among response headers %@", headers);
            return;
        }

        if(httpResponse.statusCode == 304){ // Server version matches ours, so just return ours, we're done here
            NSLog(@"Returning cached file url: %@", cachedFileUrl);
            return handler(cachedFileUrl);
        }
        
        if(httpResponse.statusCode != 200){ // Some other error that we won't like
            NSLog(@"Non-200 response for URL %@", remoteUrl);
            return;
        }
        
        NSURL* cacheFolder = [[self class] getCacheFolder:remoteUrl];
                
        NSError* fileError = nil;
        NSFileManager* fileManager = [NSFileManager defaultManager];
        
        
        // Since the server doesn't match the etag, we should delete the cached file
        if(cachedFileUrl && cachedEtag){
            [fileManager removeItemAtPath:cachedFileUrl.path error:&fileError];
            if(fileError){
                NSLog(@"Error deleting expired file %@", fileError);
            }
        }
        
        [[NSFileManager defaultManager] createDirectoryAtURL:cacheFolder withIntermediateDirectories:YES attributes:nil error:& fileError];
        if(fileError){
            NSLog(@"Error creating directories for %@: %@", cacheFolder, fileError);
            return;
        }
        
        NSURL *cacheUrl = [cacheFolder URLByAppendingPathComponent:[[self class] getCacheFile:remoteUrl forEtag:headers[@"ETag"]]];
        if([fileManager fileExistsAtPath:cacheUrl.path]){
            [fileManager removeItemAtPath:cacheUrl.path error:&fileError];
            if(fileError){
                NSLog(@"Error deleting duplicated file %@", fileError);
                return;
            }
        }
        
        [fileManager moveItemAtURL:location toURL:cacheUrl error:&fileError];
        
        if(fileError){
            NSLog(@"Error moving file to %@", fileError);
            return;
        }
        
        NSLog(@"Loaded file from url: %@ -> %@", remoteUrl, cacheUrl);
        handler(cacheUrl);
    }];
    
    [downloadTask resume];
}

+ (NSURL*)checkCacheForURL:(NSURL*)remoteUrl {
    NSURL* cacheFolder = [[self class] getCacheFolder:remoteUrl];
    NSDirectoryEnumerator *dirFiles = [[NSFileManager defaultManager] enumeratorAtPath:cacheFolder.path];
    NSString *filename;
    while ((filename = [dirFiles nextObject] )) {
        // Look for our specific file
        if ([filename hasSuffix:[remoteUrl lastPathComponent]]) {
            // Do work here
            return [cacheFolder URLByAppendingPathComponent:filename];
        }
    }
    
    return nil;
}

+ (NSString*)getCacheFile:(NSURL*)remoteUrl forEtag:(NSString*)etag {
    return [NSString stringWithFormat:@"%@-%@", [etag stringByReplacingOccurrencesOfString:@"\"" withString:@""], [remoteUrl lastPathComponent]];
}

+ (NSURL*)getCacheFolder:(NSURL*)remoteUrl {
    return [NSURL fileURLWithPathComponents:@[NSHomeDirectory(), @"Library/Caches", remoteUrl.host, [remoteUrl.path stringByDeletingLastPathComponent]]];
}

@end
