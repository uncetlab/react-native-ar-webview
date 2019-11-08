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

@interface RCNARScene : ARSCNView <ARSCNViewDelegate>

@property (nonatomic, weak) RNCWebView*  webview;

- (void)setup;

- (void)onMessage:( NSMutableDictionary<NSString *, id>* ) message;

@end

#endif /* RCNARScene_h */
