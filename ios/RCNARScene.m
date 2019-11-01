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

#import "RCNARScene.h"


@implementation RCNARScene

bool _sceneSet = NO;

- (void)setup
{
    if(_sceneSet){
        return;
    }
    
    self.autoenablesDefaultLighting = YES;
    
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

@end
