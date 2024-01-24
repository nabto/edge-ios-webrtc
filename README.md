# Native iOS Nabto Edge WebRTC

Example application that shows how you can use WebRTC with the Nabto Edge platform.

## Building

The app installs dependencies through Cocoapods, so to build and run, perform the following steps:

1. Install dependencies: `$ pod install` (see https://www.cocoapods.org for info on installation of the pod tool).

2. Open the generated workspace in XCode and work from there: `open NabtoEdgeVideo.xcworkspace`

3. Note that there is a known issue with running on iOS 17+ simulators; for now, use only on physical iOS devices

## Questions?

In case of questions or problems, please write to support@nabto.com or contact us through the live chat on [www.nabto.com](https://www.nabto.com).

## How to use

Follow the guide to start and a device and a stream and pairing with it on <https://demo.smartcloud.nabto.com/>.

Once you have an account and a connected, paired device on the website, open this app. First it will request you to log in. Once you have logged in with the account you used on the website, you should see a list of devices. If your device is paired correctly it will show up on this list. Click on your device to see your stream. 

## Troubleshooting

### Microphone permission

The app may fail to show the stream the first time around and will ask for permission to use the microphone. We are working on a fix for this, for the time being simply accept the permission and then go back to the device overview and click on your device again.

### Crash in simulator

If you observe the following crash in the simulator, you have run into a known issue. For now, please only use the app on a physical iOS device.

```
SetProperty: RPC timeout. Apparently deadlocked. Aborting now.
(lldb) bt
* thread #24, name = 'worker_thread 0x0x600003d09770', stop reason = signal SIGABRT
  * frame #0: 0x0000000108218a4c libsystem_kernel.dylib`__pthread_kill + 8
    frame #1: 0x00000001081531d0 libsystem_pthread.dylib`pthread_kill + 256
    frame #2: 0x000000018015f5ec libsystem_c.dylib`abort + 104
    frame #3: 0x00000001921e5b44 AudioToolboxCore`_ReportRPCTimeout(char const*, int) + 104
    frame #4: 0x00000001921e5cb0 AudioToolboxCore`_CheckRPCError(char const*, int, int) + 364
    frame #5: 0x00000001a7f64c40 libEmbeddedSystemAUs.dylib`AURemoteIO::SetProperty(unsigned int, unsigned int, unsigned int, void const*, unsigned int) + 564
    frame #6: 0x00000001a7f6ab9c libEmbeddedSystemAUs.dylib`AUVoiceIO::SetProperty(unsigned int, unsigned int, unsigned int, void const*, unsigned int) + 860
    frame #7: 0x00000001a7f63a74 libEmbeddedSystemAUs.dylib`AURemoteIO::Initialize() + 1048
    frame #8: 0x00000001a7fae500 libEmbeddedSystemAUs.dylib`ausdk::AUBase::DoInitialize() + 48
    frame #9: 0x00000001a7fafed4 libEmbeddedSystemAUs.dylib`ausdk::AUMethodInitialize(void*) + 48
    frame #10: 0x000000019238e87c AudioToolboxCore`AudioUnitInitialize + 128
    frame #11: 0x000000010b323df0 WebRTC`___lldb_unnamed_symbol9943 + 504
    frame #12: 0x000000010b31ec20 WebRTC`___lldb_unnamed_symbol9819 + 284
    frame #13: 0x000000010b31ea90 WebRTC`___lldb_unnamed_symbol9818 + 92
    frame #14: 0x000000010b323104 WebRTC`___lldb_unnamed_symbol9915 + 72
```

