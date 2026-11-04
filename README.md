<!-- Modified by Relocat (2026); see NOTICE. -->

> [!NOTE]
> **This is Relocat's fork of [flutter_sharing_intent](https://github.com/TSPL-Bhagat/flutter_sharing_intent)**
> by Bhagat Singh / techind.co and contributors ([pub.dev](https://pub.dev/packages/flutter_sharing_intent)).
> It is based on upstream v2.0.4 (`aa1672f547d6579585fa27df0b28ffa2a2544aaa`). It does not yet include
> later upstream changes.
>
> **Why it exists.** The [Relocat](https://relocat.org) app receives shared files straight into an
> encrypted vault, so share intake has to treat everything the sending app supplies as untrusted
> input. We reviewed the plugin (see [SECURITY_AUDIT.md](SECURITY_AUDIT.md)) and fixed what we found.
>
> **What this fork changes:**
> - **Android:**
>   - rejects non-`content://` URIs and copies every `content://` URI into the cache; no path is derived from the URI;
>   - writes each shared file into its own directory, `cache/flutter_sharing_intent/<random id>/<name>`;
>   - logs no share content (counts and types only);
>   - caps each streamed file at 16 MiB, a hard limit: one larger file drops the whole share;
>   - sanitises the provider-supplied `_display_name`, which blocks path traversal;
>   - handles intents off the main thread;
>   - prunes video thumbnails and per-share directories older than 7 days;
>   - removes the copy of a share that fails part-way, and every copy of a multi-item share if one item fails;
>   - removes the unused appcompat, material and constraintlayout dependencies.
> - **iOS:**
>   - bridges the UIScene lifecycle (the Flutter default since 3.41), so apps that use it receive shares;
>   - resolves photos off the main thread;
>   - surfaces decode errors as `DECODE_FAILED` instead of returning an empty list;
>   - caps raw `Data` payloads at 16 MiB;
>   - sanitises `lastPathComponent` (path separators and control characters removed, capped at
>     255 UTF-8 bytes on a character boundary);
>   - stops release builds from logging file names or paths;
>   - clears the App Group share-metadata plist as soon as the app reads it;
>   - writes shared files into `<container>/flutter_sharing_intent/<id>/<name>` (one directory per item).
> - **Dart / all platforms:**
>   - new `cleanup(List<String> paths)` deletes the iOS App Group copies after use; it is a no-op
>     on Android. On iOS it deletes only regular files the share extension wrote to
>     `<container>/flutter_sharing_intent/<id>/` or `<container>/flutter_sharing_intent_thumbnails/`;
>   - out-of-range media-type values and wrongly typed fields no longer crash decoding.
>
> **iOS share extension.** Copy [`ios/Classes/FSIShareViewController.swift`](ios/Classes/FSIShareViewController.swift)
> into your Share Extension target. The iOS changes above live in that file; the copy under
> `example/ios/Share Extension/` is upstream's unmodified version.
>
> **Licence.** Apache-2.0, unchanged from upstream (see [LICENSE](LICENSE)). Our modifications are
> released under the same licence; modified files are marked, and [NOTICE](NOTICE) lists them.
>
> Relocat is **not affiliated with or endorsed by** the flutter_sharing_intent maintainers.
>
> **Use the upstream package unless you need these changes.** This fork is not published to pub.dev;
> depend on it by git URL pinned to a commit.
>
> **Issues.** Problems with the changes above belong
> [here](https://github.com/relocat/flutter_sharing_intent/issues). Everything else belongs
> [upstream](https://github.com/TSPL-Bhagat/flutter_sharing_intent/issues). Report security
> issues privately to office@relocat.org.
>
> #### Fork-only API: iOS apps using the UIScene lifecycle
> UIScene is the default for Flutter iOS apps since Flutter 3.41
> ([Flutter's migration guide](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate)).
> This plugin registers only `UIApplicationDelegate` callbacks. It does not yet use the plugin
> scene API that Flutter 3.38 added (`registrar.addSceneDelegate`), because older Flutter SDKs do not
> have it. Since Flutter 3.38, `FlutterSceneDelegate` passes scene URL and user-activity events on to
> plugins that registered only application-delegate callbacks, such as this one.
>
> Flutter requires a custom `SceneDelegate` to subclass `FlutterSceneDelegate` (or conform to
> `FlutterSceneLifeCycleProvider`). In each override, call `super` first and then the plugin's
> forwarder. The forwarder covers the cases where Flutter does not pass the event on. When Flutter has
> already delivered the share, the payload is consumed and the forwarder does nothing, so a share is not
> handled twice.
> ```swift
> import Flutter
> import UIKit
> import flutter_sharing_intent
>
> class SceneDelegate: FlutterSceneDelegate {
>     override func scene(_ scene: UIScene,
>                         willConnectTo session: UISceneSession,
>                         options connectionOptions: UIScene.ConnectionOptions) {
>         super.scene(scene, willConnectTo: session, options: connectionOptions)
>         SwiftFlutterSharingIntentPlugin.handleSceneURLContexts(
>             connectionOptions.urlContexts)
>         if let activity = connectionOptions.userActivities.first {
>             SwiftFlutterSharingIntentPlugin.handleSceneUserActivity(activity)
>         }
>     }
>
>     override func scene(_ scene: UIScene,
>                         openURLContexts URLContexts: Set<UIOpenURLContext>) {
>         super.scene(scene, openURLContexts: URLContexts)
>         SwiftFlutterSharingIntentPlugin.handleSceneURLContexts(URLContexts)
>     }
>
>     override func scene(_ scene: UIScene,
>                         continue userActivity: NSUserActivity) {
>         super.scene(scene, continue: userActivity)
>         SwiftFlutterSharingIntentPlugin.handleSceneUserActivity(userActivity)
>     }
> }
> ```
>
> On a Flutter version that has no `FlutterSceneDelegate`, call the same forwarders from your own
> `UIWindowSceneDelegate`. The existing AppDelegate callbacks are preserved for apps that do not use
> UIScene.

# flutter_sharing_intent
[![pub package](https://img.shields.io/pub/v/flutter_sharing_intent.svg)](https://pub.dev/packages/flutter_sharing_intent)

A flutter plugin that allow flutter apps to receive photos, videos, text, urls or any other file types from another app.

## Features

- It's allow to share image, text, video, urls and file from other app to flutter app.
- It's allow to share multiple image, multiple video and multiple file from other app to flutter app.

## Installing

command:

```dart
 $ flutter pub add flutter_sharing_intent
```

pubspec.yaml:

```dart
dependencies:
flutter_sharing_intent: ^(latest)
```

## Usage

We are using following methods :-

- getMediaStream() \* => Sets up a broadcast stream for receiving incoming media share change events.
- getInitialSharing() \* => To get sharing data when app is start.
- reset() \* => To clear all sharing data

## Setup

### Android

Add the following intent filters to your [android/app/src/main/AndroidManifest.xml](./example/android/app/src/main/AndroidManifest.xml):

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="{YOUR_PACKAGE_NAME}">

    /// Add this permission if you want to read files from external storage
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
.....

  <application
        android:name="io.flutter.app.FlutterApplication"
        ...
        >

    <activity
            android:name=".MainActivity"
            android:configChanges="orientation|keyboardHidden|screenSize"
            android:exported="true"
            android:theme="@style/LaunchTheme"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize"
            android:screenOrientation="portrait"
            android:launchMode="singleTask">

            <!--TODO:  Add this filter, if you want support opening urls into your app-->
            <intent-filter>
               <action android:name="android.intent.action.VIEW" />
               <category android:name="android.intent.category.DEFAULT" />
               <category android:name="android.intent.category.BROWSABLE" />
               <data
                   android:scheme="https"
                   android:host="example.com"
                   android:pathPrefix="/invite"/>
            </intent-filter>

            <!--TODO: Add this filter, if you want to support sharing text into your app-->
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="text/*" />
            </intent-filter>

            <!--TODO: Add this filter, if you want to support sharing images into your app-->
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="image/*" />
            </intent-filter>

            <!--TODO: Add this filter, if you want to support sharing multi images into your app-->
            <intent-filter>
                <action android:name="android.intent.action.SEND_MULTIPLE" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="image/*" />
            </intent-filter>

            <!--TODO: Add this filter, if you want to support sharing videos into your app-->
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="video/*" />
            </intent-filter>

            <!--TODO: Add this filter, if you want to support sharing multi videos into your app-->
            <intent-filter>
                <action android:name="android.intent.action.SEND_MULTIPLE" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="video/*" />
            </intent-filter>


            <!--TODO: Add this filter, if you want to support sharing any type of files-->
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="*/*" />
            </intent-filter>

            <!--TODO: Add this filter, if you want to support sharing multiple files of any type-->
            <intent-filter>
                <action android:name="android.intent.action.SEND_MULTIPLE" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="*/*" />
            </intent-filter>
      </activity>

  </application>
</manifest>
....
```

## IOS

#### 1. Create Share Extension

- Using Xcode, go to File/New/Target and Choose "Share Extension".
- Give it a name, i.e., "Share Extension".

Make sure the deployment target for Runner.app and the share extension is the same.

#### 2. Update your [ios/Runner/Info.plist](./example/ios/Runner/Info.plist) for the following keys:

```xml
...
<key>AppGroupId</key>
<string>$(CUSTOM_GROUP_ID)</string> 
<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Editor</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>SharingMedia-$(PRODUCT_BUNDLE_IDENTIFIER)</string>
			</array>
		</dict>
	</array>

<key>NSPhotoLibraryUsageDescription</key>
<string>To upload photos, please allow permission to access your photo library.</string>
...
```


#### 3. Add the following to your [ios/Podfile](./example/ios/Podfile):
```ruby
...
target 'Runner' do
  use_frameworks!
  use_modular_headers!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))

  # Share Extension is name of Extension which you created which is in this case 'Share Extension'
  target 'Share Extension' do
    inherit! :search_paths
  end
end
...
```

#### 4. Add Runner and Share Extension in the same group

* Go to `Signing & Capabilities` tab and add App Groups capability in **BOTH** Targets: `Runner` and `Share Extension`
* Add a new container with the name of your choice. For example `group.MyContainer` in the example project its `group.com.techind.flutterSharingIntentExample`
* Add User-Defined(`Build Settings -> +`) string `CUSTOM_GROUP_ID` in **BOTH** Targets: `Runner` and `Share Extension` and set value to group id created above. You can use different group ids depends on your flavor schemes


##### Make sure the deployment target for Runner.app and the share extension is the same.


#### 5. Add the following code in [ios/Share Extension/Info.plist](./example/ios/Share%20Extension/Info.plist):

```xml
....
    <key>AppGroupId</key>
    <string>$(CUSTOM_GROUP_ID)</string>
    <key>CFBundleVersion</key>
    <string>$(FLUTTER_BUILD_NUMBER)</string>
	<key>NSExtension</key>
    <dict>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>PHSupportedMediaTypes</key>
        <array>
            <!-- To share video into your app-->
            <string>Video</string>
            <!-- To share images into your app-->
            <string>Image</string>
        </array>

        <key>NSExtensionActivationRule</key>
        <dict>
            <!-- To share text into your app -->
            <key>NSExtensionActivationSupportsText</key>
            <true/>
            <!-- TO share urls into your app -->
            <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
            <integer>1</integer>
            <!-- To share images into your app -->
            <key>NSExtensionActivationSupportsImageWithMaxCount</key>
            <integer>20</integer>
            <!-- To share video into your app -->
            <key>NSExtensionActivationSupportsMovieWithMaxCount</key>
            <integer>10</integer>
            <!-- To share other files into your app -->
            <key>NSExtensionActivationSupportsFileWithMaxCount</key>
            <integer>10</integer>
            <!-- To share plain text into your app -->
            <key>NSExtensionActivationSupportsPlainText</key>
            <true/>
          
        </dict>
    </dict>
    <key>NSExtensionMainStoryboard</key>
    <string>MainInterface</string>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.share-services</string>
    </dict>
....
```


[//]: # (#### 5. Add following code to [ios/Runner/Runner.entitlements]&#40;./example/ios/Runner/Runner.entitlements&#41;:)

[//]: # ()
[//]: # ()
[//]: # (```xml)

[//]: # (....)

[//]: # (    <!--TODO:  Add this tag-->)

[//]: # (    <key>com.apple.security.application-groups</key>)

[//]: # (    <array>)

[//]: # (    <string>group.com.techind.flutterSharingIntentExample</string>)

[//]: # (    </array>)

[//]: # (....)

[//]: # (```)

[//]: # ()
[//]: # (Here `group.com.techind.flutterSharingIntentExample` is the App Group ID created in previous step.)

#### 6. Add file [FSIShareViewController.swift](./example/ios/Share%20Extension/FSIShareViewController.swift)  to  [ios/Share Extension/FSIShareViewController.swift](./example/ios/Share%20Extension/FSIShareViewController.swift):
You can get the file from [here](./example/ios/Share%20Extension/FSIShareViewController.swift)

##### Make your `ShareViewController` [ios/Share Extension/ShareViewController.swift](./example/ios/Share%20Extension/ShareViewController.swift) inherit from `FSIShareViewController`:

```swift

class ShareViewController: FSIShareViewController {
    
}
```

#### 7. Add following code in your host app AppDelegate file - [ios/Runner/AppDelegate.swift](./example/ios/Runner/AppDelegate.swift)
> **⚠️ IMPORTANT NOTE**  
> Do **NOT** replace your existing `AppDelegate.swift` file or remove any existing code.  
> You should **add the following snippet** to your current file and merge it with your existing logic.  
> Keep any other URL handling logic you already have (Firebase, uni_links, deep links, etc.).

```swift
    import flutter_sharing_intent
    ....
    override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {

     let sharingIntent = SwiftFlutterSharingIntentPlugin.instance
     /// if the url is made from SwiftFlutterSharingIntentPlugin then handle it with plugin [SwiftFlutterSharingIntentPlugin]
     if sharingIntent.hasSameSchemePrefix(url: url) {
         return sharingIntent.application(app, open: url, options: options)
     }

     // Proceed url handling for other Flutter libraries like uni_links
     return super.application(app, open: url, options:options)
   }
    ....
```

## Full Example

```dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_sharing_intent/flutter_sharing_intent.dart';
import 'package:flutter_sharing_intent/model/sharing_file.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late StreamSubscription _intentDataStreamSubscription;
  List<SharedFile>? list;
  @override
  void initState() {
    super.initState();
    // For sharing images coming from outside the app while the app is in the memory
    _intentDataStreamSubscription = FlutterSharingIntent.instance.getMediaStream()
        .listen((List<SharedFile> value) {
      setState(() {
        list = value;
      });
      print("Shared: getMediaStream ${value.map((f) => f.value).join(",")}");
    }, onError: (err) {
      print("getIntentDataStream error: $err");
    });

    // For sharing images coming from outside the app while the app is closed
    FlutterSharingIntent.instance.getInitialSharing().then((List<SharedFile> value) {
      print("Shared: getInitialMedia ${value.map((f) => f.value).join(",")}");
      setState(() {
        list = value;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Container(
              margin: EdgeInsets.symmetric(horizontal: 24),
              child: Text('Sharing data: \n${list?.join("\n\n")}\n')),
        ),
      ),
    );
  }
  @override
  void dispose() {
    _intentDataStreamSubscription.cancel();
    super.dispose();
  }
}
```

## Troubleshooting

* Error: No such module 'flutter_sharing_intent'
  *  Fix: Go to Build Phases of your Runner target and move `Embed Foundation Extension` to the top of `Thin Binary`.


* Error: App does not build after adding Share Extension?
  * Fix: Check Build Settings of your share extension and remove everything that tries to import Cocoapods from your main project. i.e. remove everything under `Linking/Other Linker Flags` 

* You might need to disable bitcode for the extension target

* Error: Invalid Bundle. The bundle at 'Runner.app/Plugins/Sharing Extension.appex' contains disallowed file 'Frameworks'
    * Fix: https://stackoverflow.com/a/25789145/2061365