# React Native AR Webview

This React Native library is a fork of the popular [React Native Webivew](https://github.com/react-native-community/react-native-webview) project, created for the Reese Innovation Lab's [AR News Reader](https://github.com/uncetlab/react-native-ar-webview/tree/master) app.

It provides a React Native component that contains a WebView layered on top of a RealityKit AR view, controllable through javascript running on the provided webpage.

If you want to write a webpage that interfaces with the AR view, read the documentation for our custom [ARView.js](https://github.com/uncetlab/AR-Assets/tree/master/assets#arviewjs) library, which contains methods for placing and maniuplating `.usdz` and `.reality` files in AR.

## Developement Notes
Most of the custom AR code for this project is contained in [`ARManager.swift`](https://github.com/uncetlab/react-native-ar-webview/blob/master/ios/ARManager.swift), a class that manages and updates the AR View behind the transparent WebView.

Messages are passed between the WebView and the ARView as JSON objects using a javascript `postMessage` interface, which are initially recieved by the WebView's view controller and then passed onto the `ARManager`.

This library implements caching based on the `ETag` header of the USDZ files, so you should host those files on a server providing that feature (like AWS's S3). If the `ETag` of the file on the server matches the locally cached version, the library will use the local copy instead of downloading a (presumably identitical) version.

It currently is only implemented for iOS devices, although it should be easy to replicate the interface with Android / ARCore, by duplicating the behavior for each message type passed from the WebView. 
