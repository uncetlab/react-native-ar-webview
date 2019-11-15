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

API_AVAILABLE(ios(11.0))
@implementation RCNARScene

bool _sceneSet = NO;
bool _hasItem = NO;

ARPlaneAnchor *_planeAnchor;
SCNScene *_loadedScene;
ARCoachingOverlayView *_arCoachingOverlay;
NSDictionary<NSString *, id> *_initOptions;
SCNNode *_placeMarker = nil;
SCNVector3 _placement;
CGFloat center_x = 0.0;
CGFloat center_y = 0.0;
int _updateCounter = 0;

- (void)setup API_AVAILABLE(ios(11.0)){
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

    ARWorldTrackingConfiguration *configuration = [ARWorldTrackingConfiguration new];
    configuration.planeDetection = ARPlaneDetectionHorizontal;
    
    [self.session runWithConfiguration:configuration];
    _sceneSet = YES;
    
    NSLog(@"InitOptions %@", _initOptions);
}

- (void)setupCoachingOverlay API_AVAILABLE(ios(13.0)) {
    _arCoachingOverlay = [[ARCoachingOverlayView alloc] init];
    _arCoachingOverlay.session = self.session;
    _arCoachingOverlay.activatesAutomatically = YES;
    _arCoachingOverlay.goal = ARPlaneDetectionHorizontal;
    
    _arCoachingOverlay.translatesAutoresizingMaskIntoConstraints = NO;
    [self.superview addSubview:_arCoachingOverlay];
    
    [_arCoachingOverlay.topAnchor constraintEqualToAnchor:self.topAnchor].active = YES;
    [_arCoachingOverlay.leftAnchor constraintEqualToAnchor:self.leftAnchor].active = YES;
    [_arCoachingOverlay.bottomAnchor constraintEqualToAnchor:self.bottomAnchor].active = YES;
    [_arCoachingOverlay.rightAnchor constraintEqualToAnchor:self.rightAnchor].active = YES;
}

- (void)setupRaycastPoint {
    SCNPlane *plane = [SCNPlane planeWithWidth:0.25 height:0.25];
    plane.firstMaterial.diffuse.contents = UIColor.blackColor;
    plane.cornerRadius = 0.25;
    _placeMarker = [SCNNode nodeWithGeometry:plane];
    _placeMarker.eulerAngles = SCNVector3Make(-M_PI_2, 0, 0);
    _placeMarker.opacity = 0.75;
    [self updateRaycastPoint];
    [self.scene.rootNode addChildNode:_placeMarker];
}

- (void)updateRaycastPoint {
    ARRaycastQuery *query = [self raycastQueryFromPoint:CGPointMake(center_x,center_y) allowingTarget:ARHitTestResultTypeEstimatedHorizontalPlane alignment:ARRaycastTargetAlignmentHorizontal];
    NSArray<ARRaycastResult *> *results = [self.session raycast:query];
   
    if(results && [results count]){
        _placement = SCNVector3Make(results[0].worldTransform.columns[3].x, results[0].worldTransform.columns[3].y, results[0].worldTransform.columns[3].z);
        _placeMarker.position = _placement;
    }
}

- (void)initSceneFromUrl:(NSURL*) url API_AVAILABLE(ios(11.0)){
    center_x = self.bounds.origin.x + self.bounds.size.width/2.0;
    center_y = self.bounds.origin.y + self.bounds.size.height/2.0;
    
    // Only enable coaching overlay if enabled, and iOS > v13
    if([_initOptions objectForKey:@"coachingOverlay"])
        if(@available(iOS 13, *))
           [self setupCoachingOverlay];
    
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

- (void)placeLoadedSceneObjects API_AVAILABLE(ios(11.0)){
    if(_loadedScene && _planeAnchor){
        NSLog(@"Placing objects...");
        
        float camAngle = self.session.currentFrame.camera.eulerAngles[1];
        float scale = _initOptions[@"scale"] || 1.0;
        for(SCNNode *node in _loadedScene.rootNode.childNodes){
            node.position = _placement;
            node.scale = SCNVector3Make(scale, scale, scale);
            node.eulerAngles = SCNVector3Make(0, camAngle, 0);
            [self.scene.rootNode addChildNode:node];
        }
        
        if(_placeMarker){
            [_placeMarker removeFromParentNode];
            _placeMarker = nil;
        }
        _hasItem = YES;
        
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
        _initOptions = message[@"data"][@"options"];
        
        if(!_initOptions || !_initOptions[@"url"]){
            NSLog(@"Error: Action is init, but no URL was provided.");
            return;
        }
        
        NSURL *url = [NSURL URLWithString:_initOptions[@"url"]];
        if(!url){
            NSLog(@"Error: Malformed URL for '%@' action: %@ ", action, _initOptions[@"url"]);
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

// MARK: - ARSCNViewDelegate

/**
 * SceneKit delegate methods
**/
- (void)renderer:(id<SCNSceneRenderer>)renderer didAddNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor  API_AVAILABLE(ios(11.0)){
    
    if (_planeAnchor || ![anchor isKindOfClass:[ARPlaneAnchor class]]) {
      return;
    }
    ARPlaneAnchor *plane = (ARPlaneAnchor*)anchor;
    _planeAnchor = plane;
    
    if(_placeMarker)
        [self updateRaycastPoint];
    else if(!_hasItem)
        [self setupRaycastPoint];
    
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

- (void)renderer:(id<SCNSceneRenderer>)renderer updateAtTime:(NSTimeInterval)time {
    if(_placeMarker != nil)
        [self updateRaycastPoint];
}


// MARK: - RCNARScene Helpers

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
