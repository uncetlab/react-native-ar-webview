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
#include <math.h>
#import "RCNARScene.h"

API_AVAILABLE(ios(13.0))
@implementation RCNARScene

bool _sceneReady = NO;
bool _hasItem = NO;
NSString* _currentItem = nil;

NSURLCache *_urlCache = nil;
ARWorldTrackingConfiguration *_configuration = nil;
NSMutableDictionary<NSString *,SCNScene*> *_loadedScenes;
ARCoachingOverlayView *_arCoachingOverlay;
SCNNode *_placeMarker = nil;
simd_float3 _placement;
CGFloat center_x = 0.0;
CGFloat center_y = 0.0;
CGFloat _camAngle = NAN;
int _updateCounter = 0;

- (void)start {
    NSLog(@"Running AR...");
    if(!_urlCache){
        _urlCache = [[NSURLCache alloc] initWithMemoryCapacity: 100 * 1024 * 1024 // 25mb (~5 models)
                                                             diskCapacity: 400 * 1024 * 1024 // 400mb (~20 models)
                                                                 diskPath:nil];
    }
    [NSURLCache setSharedURLCache:_urlCache];
    if(!_loadedScenes || ![_loadedScenes count]){
        _loadedScenes = [[NSMutableDictionary<NSString*,SCNScene*> alloc] init];
    }
    if(!_configuration){
        _configuration = [ARWorldTrackingConfiguration new];
        _configuration.autoFocusEnabled = NO;
        _configuration.planeDetection = ARPlaneDetectionHorizontal;
    }
    
    SCNScene *scene = [SCNScene new];
    self.scene = scene;
    self.delegate = self;
//    self.debugOptions = ARSCNDebugOptionShowFeaturePoints;
    self.autoenablesDefaultLighting = YES;
    self.automaticallyUpdatesLighting = YES;
    
    [self.session runWithConfiguration:_configuration];
    _hasItem = NO;
}

- (void)pause {
    NSLog(@"Pausing setup");
    [self.session pause];
}

- (void)setupCoachingOverlay {
    _arCoachingOverlay = [[ARCoachingOverlayView alloc] init];
    _arCoachingOverlay.delegate = self;
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
    SCNPlane *plane = [SCNPlane planeWithWidth:0.5 height:0.5];
    plane.firstMaterial.diffuse.contents = UIColor.blackColor;
    plane.cornerRadius = 0.5;
    _placeMarker = [SCNNode nodeWithGeometry:plane];
    _placeMarker.eulerAngles = SCNVector3Make(-M_PI_2, 0, 0);
    _placeMarker.opacity = 0.85;
    [self updateRaycastPoint];
    [self.scene.rootNode addChildNode:_placeMarker];
    _sceneReady = YES;
    [self sendMessage:@{
      @"event": @"plane"
    }];
}

- (void)updateRaycastPoint {
    ARRaycastQuery *query = [self raycastQueryFromPoint:CGPointMake(center_x,center_y) allowingTarget:ARRaycastTargetExistingPlaneGeometry alignment:ARRaycastTargetAlignmentHorizontal];
    NSArray<ARRaycastResult *> *results = [self.session raycast:query];
   
    if(results && [results count]){
        _placement = simd_make_float3(results[0].worldTransform.columns[3].x, results[0].worldTransform.columns[3].y, results[0].worldTransform.columns[3].z);
        _placeMarker.simdPosition = _placement;
        _camAngle = self.session.currentFrame.camera.eulerAngles[1];
    }
}

- (void)initAssetFrom:(NSURL*)url forKey:(NSString*)key withOptions:(NSDictionary<NSString*,id>*)options {
    if(_loadedScenes[key]){
        NSLog(@"Scene %@ already exists", key);
        [self sendMessage:@{
          @"event": @"loaded",
          @"asset": key
        }];
        return;
    }
    
    [[self class] downloadAssetURL:url completionHandler:^(NSURL* location) {
        NSError *sceneError = nil;

        SCNScene *scene = [SCNScene sceneWithURL:location options:nil error:&sceneError];
        NSLog(@"Scene is %@", scene);
        [_loadedScenes setObject:scene forKey:key];
        NSLog(@"Set loadedScenes value for key %@", key);
        NSLog(@"value is %@", _loadedScenes);
        self.sceneTime = 0;
        
        
        [self addAnimationEventsOn:_loadedScenes[key].rootNode withKey:key];
    
        [self sendMessage:@{
          @"event": @"loaded",
          @"asset": key
        }];
                
        if(sceneError){
            NSLog(@"Scene error: %@", sceneError);
        }
    }];
}

- (void)placeLoadedSceneObject:(NSString*)key withOptions:(NSDictionary<NSString*,id>*)options {
    if(_sceneReady && _loadedScenes[key]){
        
        if(_currentItem){
            NSLog(@"Removing current item %@", _currentItem);
            [_loadedScenes[_currentItem].rootNode removeFromParentNode];
        }
        
        NSLog(@"Placing object %@...", key);
        float scale = [options objectForKey:@"scale"] ? [options[@"scale"] floatValue] : 1.0f;
        NSLog(@"Rendering at scale %f", scale);
        
        _loadedScenes[key].rootNode.scale = SCNVector3Make(scale, scale, scale);
        
        NSDictionary<NSString*,id> *r = [options objectForKey:@"rotation"];
        if(r && [r objectForKey:@"x"] && [r objectForKey:@"y"] && [r objectForKey:@"z"]){
            NSLog(@"Applying rotation to %@ <%@,%@,%@>", key, r[@"x"], r[@"y"], r[@"z"]);
            _loadedScenes[key].rootNode.eulerAngles = SCNVector3Make([r[@"x"] floatValue], _camAngle + [r[@"y"] floatValue], [r[@"z"] floatValue]);
        }else{
            _loadedScenes[key].rootNode.eulerAngles = SCNVector3Make(0, _camAngle, 0);
        }
        
        NSDictionary<NSString*,id> *t = [options objectForKey:@"translation"];
        if(t && [t objectForKey:@"x"] && [t objectForKey:@"y"] && [t objectForKey:@"z"]){
            simd_float3 translation = simd_make_float3([t[@"x"] floatValue], [t[@"y"] floatValue], [t[@"z"] floatValue]);
            NSLog(@"Applying translation to %@ <%f,%f,%f>", key, translation.x, translation.y, translation.z);
            _loadedScenes[key].rootNode.simdPosition = _placement + translation;
        }else{
            _loadedScenes[key].rootNode.simdPosition = _placement;
        }
                
        [self.scene.rootNode addChildNode:_loadedScenes[key].rootNode];
        
        _currentItem = key;
        
        if(_placeMarker){
            [_placeMarker removeFromParentNode];
            _placeMarker = nil;
        }
        _hasItem = YES;
        
        [self sendMessage:@{
          @"event": @"rendered",
          @"asset": key
        }];
        
    }else{
        if(!_sceneReady)
            NSLog(@"Scene has not yet found a plane");
        if(!_loadedScenes[key])
            NSLog(@"No scene is available for %@", key);
        NSLog(@"Loaded Scenes %@", _loadedScenes);
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
        if(![data objectForKey:@"assets"]){
            NSLog(@"Error: Action is init, but no assets were provided.");
            return;
        }
        
        center_x = self.bounds.origin.x + self.bounds.size.width/2.0;
        center_y = self.bounds.origin.y + self.bounds.size.height/2.0;
        NSLog(@"INIT XY (%f,%f)", center_x, center_y);
        
        NSDictionary<NSString *,id> *assets = [data objectForKey:@"assets"];
        for(NSString *key in [assets keyEnumerator]){
            NSURL *url = [NSURL URLWithString:assets[key][@"url"]];
            if(!url){
                NSLog(@"Error: Malformed URL for asset '%@': %@ ", key, assets[key][@"url"]);
                return;
            }
            [self initAssetFrom:url forKey:key withOptions:assets[key]];
        }
        
        // Only enable coaching overlay if enabled, and iOS > v13
       if([data objectForKey:@"coachingOverlay"])
          [self setupCoachingOverlay];
        
    }else if([action isEqualToString:@"place"]){
        NSLog(@"Attempting to place object %@", [data objectForKey:@"asset"]);
        if(![data objectForKey:@"asset"]){
            NSLog(@"'asset' is required");
            return;
        }
        [self placeLoadedSceneObject:message[@"data"][@"asset"] withOptions:message[@"data"]];
    }else if([action isEqualToString:@"play"]){
        [[self class] playAllAnimationsOn:self.scene.rootNode withRepeat:[message[@"data"] objectForKey:@"loop"]];
    }else{
        NSLog(@"Error: Unrecognized action: %@", action);
    }
}

// MARK: - ARCoachingOverlayViewDelegate

- (void)coachingOverlayViewWillActivate:(ARCoachingOverlayView *)coachingOverlayView {
    NSLog(@"Coaching overlay shown");
    _sceneReady = NO;
    _hasItem = NO;
    [self sendMessage:@{
        @"event": @"overlyShown"
    }];
}

- (void)coachingOverlayViewDidDeactivate:(ARCoachingOverlayView*)view {
    NSLog(@"Coaching overlay hidden");
    _sceneReady = YES;
    [self sendMessage:@{
      @"event": @"overlayHidden"
    }];
}

// MARK: - ARSCNViewDelegate

/**
 * SceneKit delegate methods
**/
- (void)renderer:(id<SCNSceneRenderer>)renderer didAddNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor {
//    NSLog(@"SessionDelegate didAddNode %@ forAnchor %@", node, anchor);
    if(_placeMarker)
        [self updateRaycastPoint];
    else if(!_hasItem)
        [self setupRaycastPoint];
}

- (void)renderer:(id<SCNSceneRenderer>)renderer didRemoveNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor {
//    NSLog(@"SessionDelegate didRemoveNode %@ forAnchor %@", node, anchor);
}

- (void)renderer:(id<SCNSceneRenderer>)renderer updateAtTime:(NSTimeInterval)time {
    if(_placeMarker) [self updateRaycastPoint];
}

// MARK: - ARSessionObserver

- (void)session:(ARSession *)session cameraDidChangeTrackingState:(ARCamera *)camera{
//    NSLog(@"SessionDelegate session:%@ cameraDidChangeTrackingState: %@", session, camera);
    if(camera.trackingState == ARTrackingStateNormal){
        [self sendMessage:@{
            @"event": @"tracking"
        }];
    }
}
- (void)sessionWasInterrupted:(ARSession *)session{
//    NSLog(@"SessionDelegate sessionWasInterrupted: %@", session);
}
- (void)sessionInterruptionEnded:(ARSession *)session{
//    NSLog(@"SessionDelegate sessionInterruptionEnded: %@", session);
}
- (void)session:(ARSession *)session didFailWithError:(NSError *)error{
//    NSLog(@"SessionDelegate session:%@ didFailWithError: %@", session, error);
}


// MARK: - RCNARScene Helpers

- (void)addAnimationEventsOn:(SCNNode*)node withKey:(NSString*)assetKey {
    __block RCNARScene *blocksafeSelf = self;
    for(SCNNode *n in node.childNodes){
        for(NSString *key in n.animationKeys){
            [n animationPlayerForKey:key].animation.repeatCount = 1;
            NSLog(@"Adding for stop");
            [n animationPlayerForKey:key].animation.animationDidStop = ^(SCNAnimation * _Nonnull animation, id<SCNAnimatable> _Nonnull receiver, BOOL completed){
                [blocksafeSelf sendMessage:@{
                    @"event": @"animation",
                    @"asset": assetKey,
                    @"animation": key,
                    @"status": completed ? @"stopped" : @"started"
                }];
            };
        }
        [self addAnimationEventsOn:n withKey:assetKey];
    }
}

+(void)pauseAllAnimationsOn:(SCNNode*)node {
    for(SCNNode *n in node.childNodes){
        if(n.animationKeys.count > 0){
            for(NSString *key in n.animationKeys){
                [[n animationPlayerForKey:key] setPaused:YES];
            }
        }
        [[self class] pauseAllAnimationsOn:n];
    }
}
+(void)playAllAnimationsOn:(SCNNode*)node withRepeat:(bool)repeat{
    for(SCNNode *n in node.childNodes){
       if(n.animationKeys.count > 0){
           for(NSString *key in n.animationKeys){
//               if(!repeat){
                   [n animationPlayerForKey:key].animation.repeatCount = 1;
//               }
               [[n animationPlayerForKey:key] play];
           }
       }
       [[self class] playAllAnimationsOn:n withRepeat:repeat];
   }
}

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
