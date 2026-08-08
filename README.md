# iOS26Spoofer

A rootless jailbreak tweak that reports iPadOS 26.0 at runtime inside selected
system apps. It does not modify the device's system-version files.

## Targets

- Settings (`com.apple.Preferences`)
- App Store (`com.apple.AppStore`)
- `UIDevice.systemVersion` returns `26.0`
- `NSProcessInfo.operatingSystemVersion` returns `26.0.0`
- `NSProcessInfo.operatingSystemVersionString` returns an iOS 26 version string
- `NSProcessInfo.isOperatingSystemAtLeastVersion:` compares against `26.0.0`
- MobileGestalt's `ProductVersion` answer returns `26.0`

## Windows build

1. Create a new GitHub repository.
2. Upload the contents of this folder to the repository.
3. Open the repository's Actions tab.
4. Run the Build iOS26Spoofer workflow.
5. Open the completed workflow run.
6. Download the iOS26Spoofer-deb artifact.
7. Extract the artifact ZIP to get the .deb package.
8. Transfer the .deb to the iPad and install it with Sileo, Zebra, Filza, or dpkg.
9. Respring.

Command-line installation:

```sh
dpkg -i com.roboa.ios26spoofer_1.0.0_iphoneos-arm64.deb
```

## Important

This does not provide real iPadOS 26 frameworks or APIs. Software requiring APIs
that are unavailable on the installed OS can still fail to install, launch, or
function. Removing the tweak and respringing restores the real reported version.
