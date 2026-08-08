# iOS26Spoofer

A rootless jailbreak tweak that reports iPadOS 26.0 at runtime. Its Settings
page can enable or disable spoofing and choose About Only, Apps Only, or Both.
It does not modify the device's system-version files.

## Targets

- Settings About page (`com.apple.Preferences`), including a direct label fallback
- UIKit apps and the App Store's StoreKit product-page processes when Apps Only
  or Both is selected
- `UIDevice.systemVersion` returns `26.0`
- `NSProcessInfo.operatingSystemVersion` returns `26.0.0`
- `NSProcessInfo.operatingSystemVersionString` returns an iOS 26 version string
- `NSProcessInfo.isOperatingSystemAtLeastVersion:` compares against `26.0.0`
- MobileGestalt's `ProductVersion` answer returns `26.0`

## Configuration

Open Settings and select **iOS26Spoofer**. The scope choices are:

- **About Only**: spoof the Settings About page only.
- **Apps Only**: spoof version APIs in UIKit apps, excluding Settings.
- **Both**: spoof the About page and UIKit apps.

The tweak is disabled by default. Turning it on triggers a respring. Its default
scope is **Both**; choose About Only if app compatibility problems occur.

The **Runtime Log** page records process loading, hook installation, and the
first call to each version API so failed interception can be diagnosed. Use
**Copy Log** there to copy the complete diagnostic text.

Changes are broadcast immediately, but an app may cache its version. Close and
reopen Settings or the affected app after changing an option.

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
dpkg -i com.roboa.ios26spoofer_1.2.1_iphoneos-arm64.deb
```

## Important

This does not provide real iPadOS 26 frameworks or APIs. Software requiring APIs
that are unavailable on the installed OS can still fail to install, launch, or
function. The App Store also uses each app's `MinimumOSVersion` metadata when it
decides compatibility, so changing runtime version answers is not a guaranteed
installation bypass. Removing the tweak and respringing restores the real
reported version.
