<!-- Modified by Relocat (2026); see NOTICE. -->

# Changelog
All notable changes to this project will be documented in this file.

## Unreleased (Relocat fork, based on 2.0.4)
* Android: reject non-`content://` URIs; cap each streamed file at 16 MiB (hard limit; one larger file drops the whole share); truncate `_display_name` on a code point boundary; sanitise the provider-supplied `_display_name` (path traversal); handle intents off the main thread; prune video thumbnails older than 7 days; remove the unused appcompat, material and constraintlayout dependencies.
* iOS: UIScene lifecycle bridging; resolve photos off the main thread; surface decode errors as `DECODE_FAILED`; cap raw `Data` payloads at 16 MiB; sanitise `lastPathComponent` (strip path separators and control characters, cap at 255 UTF-8 bytes on a character boundary); no file names or paths in release logs; clear the App Group share-metadata plist once the app reads it; `cleanup` deletes only paths strictly inside the App Group container (path-component check, `..` rejected).
* Android: every `content://` URI is copied into the cache and no path is derived from the URI (FSI-100); share content is no longer logged (FSI-101); each shared file gets its own directory `cacheDir/flutter_sharing_intent/<random id>/<name>`, thumbnails move to `cacheDir/flutter_sharing_intent_thumbnails/`, and stale entries are pruned (FSI-102).
* iOS: `cleanup` removes only regular files, never directories or symbolic links (FSI-103).
* Dart: new `cleanup(List<String> paths)` deletes the iOS App Group copies (no-op on Android); out-of-range media-type values and wrongly typed fields no longer crash decoding.
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

