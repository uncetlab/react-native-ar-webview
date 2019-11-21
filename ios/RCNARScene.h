//
//  RCNARScene.h
//  RNCWebView
//
//  Created by Peter Andringa on 10/28/19.
//  Copyright © 2019 Facebook. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <ARKit/ARKit.h>
#import <WebKit/WebKit.h>
#import <SceneKit/SceneKit.h>

#import "RNCWebView.h"

#ifndef RCNARScene_h
#define RCNARScene_h

API_AVAILABLE(ios(13.0))
@interface RCNARScene : ARSCNView <ARSCNViewDelegate, ARCoachingOverlayViewDelegate>

@property (nonatomic, weak) RNCWebView*  webview;

- (void)start;
- (void)pause;

- (void)onMessage:( NSMutableDictionary<NSString *, id>* ) message;

- (void)coachingOverlayViewWillActivate:(ARCoachingOverlayView*)view;
- (void)coachingOverlayViewDidDeactivate:(ARCoachingOverlayView*)view;

- (void)renderer:(id<SCNSceneRenderer>)renderer didAddNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor;
- (void)renderer:(id<SCNSceneRenderer>)renderer didRemoveNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor;
- (void)renderer:(id<SCNSceneRenderer>)renderer updateAtTime:(NSTimeInterval)time;

- (void)session:(ARSession *)session cameraDidChangeTrackingState:(ARCamera *)camera;
- (void)sessionWasInterrupted:(ARSession *)session;
- (void)sessionInterruptionEnded:(ARSession *)session;
- (void)session:(ARSession *)session didFailWithError:(NSError *)error;

@end

#endif /* RCNARScene_h */
