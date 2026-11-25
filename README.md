# GoshVideoTest

A minimal Android demo for validating local video decoding and transcoding with `awesome_video_kit` `v0.0.5`.

## Features

- Select a local video from the Android gallery
- Read source media information
- Transcode the video to MP4
- Read and verify output media information
- Show full diagnostic logs in the app
- Capture only AwesomeVideoKit native error logs
- Copy logs for troubleshooting
- Show bilingual English / Spanish success and failure SnackBars

## Download

Open the latest [GitHub Release](../../releases/latest) on an Android phone and download the `arm64-v8a` APK.

The APK is intended for most modern Android phones. Older 32-bit devices can use the `armeabi-v7a` asset when it is available.

## Install

If Android blocks the installation, allow installation from the browser or file manager being used to open the APK, then retry.

## Build

```bash
flutter pub get
flutter analyze lib/main.dart
flutter build apk --release --split-per-abi
```

The app uses `awesome_video_kit` from GitHub at ref `v0.0.5`.
