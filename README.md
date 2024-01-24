# Native iOS Nabto Edge WebRTC

Example application that shows how you can use WebRTC with the Nabto Edge platform.

## Building

The app installs dependencies through Cocoapods, so to build and run, perform the following steps:

1. Install dependencies: `$ pod install` (see https://www.cocoapods.org for info on installation of the pod tool).

2. Open the generated workspace in XCode and work from there: `open NabtoEdgeVideo.xcworkspace`

## Questions?

In case of questions or problems, please write to support@nabto.com or contact us through the live chat on [www.nabto.com](https://www.nabto.com).

## How to use

Follow the guide to start and a device and a stream and pairing with it on <https://demo.smartcloud.nabto.com/>.

Once you have an account and a connected, paired device on the website, open this app. First it will request you to log in. Once you have logged in with the account you used on the website, you should see a list of devices. If your device is paired correctly it will show up on this list. Click on your device to see your stream. Note that the app may fail to show the stream the first time around and will ask for permission to use the microphone. We are working on a fix for this, for the time being simply accept the permission and then go back to the device overview and click on your device again.
