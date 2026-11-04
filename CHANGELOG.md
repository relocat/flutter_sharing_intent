<!-- Modified by Relocat (2026); see NOTICE. -->

# Changelog
All notable changes to this project will be documented in this file.

## Unreleased (Relocat fork, based on 2.0.4)
* Android: reject non-`content://` URIs; cap each streamed file at 16 MiB (hard limit; one larger file drops the whole share); truncate `_display_name` on a code point boundary; sanitise the provider-supplied `_display_name` (path traversal); handle intents off the main thread; prune video thumbnails older than 7 days; remove the unused appcompat, material and constraintlayout dependencies.
* iOS: UIScene lifecycle bridging; resolve photos off the main thread; surface decode errors as `DECODE_FAILED`; cap raw `Data` payloads at 16 MiB; sanitise `lastPathComponent` (strip path separators and control characters, cap at 255 UTF-8 bytes on a character boundary); no file names or paths in release logs; clear the App Group share-metadata plist once the app reads it; `cleanup` deletes only paths strictly inside the App Group container (path-component check, `..` rejected).
* Android: every `content://` URI is copied into the cache and no path is derived from the URI (FSI-100); share content is no longer logged (FSI-101); each shared file gets its own directory `cacheDir/flutter_sharing_intent/<random id>/<name>`, thumbnails move to `cacheDir/flutter_sharing_intent_thumbnails/`, and stale entries are pruned (FSI-102).
* Android: a failed copy removes its directory and, for a multi-item share, every copy of that share (FSI-104); a bad thumbnail or duration no longer drops the share; cache roots are re-created on every use; recursive deletes never follow symbolic links.
* Android: the plugin no longer uses java.nio.file (API 26) calls; links are detected with `lstat`. A failing delete no longer stops the others, a failed thumbnail write leaves no file, and the thumbnails of a dropped share are deleted. `cleanup` now deletes the plugin's own copies.
* Dart: `cleanup` now returns the number of files it removed (Android and iOS).
* iOS share extension: staged files and directories use complete file protection and only regular files are copied; shared state is serialised and a cancelled or failed share is never delivered; symlinked plugin directories are refused; everything staged is deleted on cancel and on error; the bundle id in the redirect URL is strictly percent-encoded; release builds no longer compile the debug logger; removed the unused `writeTempFile` (FSI-107).
* iOS: thumbnails must be `<UUID>.jpg`; plugin directories that are symbolic links are refused; emptied directories are removed with a non-recursive `rmdir`; file URLs are percent-decoded; a failed thumbnail write leaves no file.
* iOS: `cleanup` removes only regular files, never directories or symbolic links (FSI-103). The share extension now writes `<container>/flutter_sharing_intent/<UUID>/<name>` and thumbnails to `<container>/flutter_sharing_intent_thumbnails/<UUID>.jpg`, and `cleanup` deletes only files of that shape (FSI-105).
* Dart: new `cleanup(List<String> paths)` deletes the plugin's own copies (iOS App Group directories; Android cache directories and thumbnails); out-of-range media-type values and wrongly typed fields no longer crash decoding.
* Added SECURITY_AUDIT.md and NOTICE. No version bump.

## 2.0.4
* Fixed iOS issue #72
* Update README.md

## 2.0.3
* Update README.md iOS setup instructions
* Fixed iOS issues -  #65, #55, #41, #4


## 2.0.2
* Update README.md iOS setup instructions

## 2.0.1
* Update README.md iOS setup instructions

## 2.0.0
* Bug fix for iOS share extension not working in certain scenarios
* Update example app dependencies
* Update plugin dependencies
* Update README.md example code
* Update plugin iOS code


## 1.1.2
* Add support for Apple Privacy Manifest #58


## 1.1.1
* Fixed iOS issue #41
* Update android target SDK to 34
* Update app build.gradle

