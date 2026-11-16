# GRAMO_APP · Project rename and publication

Date: 2026-11-16 (Asia/Shanghai).

## What changed

| Before | Now |
|---|---|
| `ZhiWeiShao.xcodeproj` | `GRAMO_APP.xcodeproj` |
| `ZhiWeiShao` scheme / app target / Swift module | `GRAMO_APP` |
| `ZhiWeiShaoTests` | `GRAMO_APPTests` |
| `ZhiWeiShaoUITests` | `GRAMO_APPUITests` |
| `ZhiWeiShao/` source folder | `GRAMO_APP/` |
| `ZhiWeiShaoApp.swift` entry point | `GRAMO_APPApp.swift` |
| App product / display name | `GRAMO_APP.app` / `GRAMO_APP` |

Updated the shared scheme, build products, test host executable, UI test target, `@testable import` statements, simulator launcher and current setup documentation. The simulator launcher now selects an available iOS 18+ iPhone instead of requiring this developer's simulator UUID; `GRAMO_SIM_ID` can override it.

The parent checkout directory may retain its local name. Open the renamed `.xcodeproj` inside it; the parent folder does not determine the project or app name.

## Preserved

- Application Bundle ID: `com.kanglaide.zhiweishao`; test Bundle IDs unchanged.
- Signing flags and development-team settings, compared against the Git baseline.
- Existing persistence keys, stored meals, preferences and mode isolation.
- BLE UUIDs, firmware device names, model metadata and product artwork.
- Original Git commits. This is an additive commit, not a new repository initialization or history rewrite.

Existing NOMI branding in the product UI and NOMI01 in the hardware protocol remain intentional. Historical JSON evidence retains its original project names, timestamps and hashes.

## Verification

- `xcodebuild -list`: project/scheme `GRAMO_APP`, app + unit + UI targets correctly discovered.
- Debug Simulator build and test: **31 unit tests + 6 UI tests passed**, iPhone 16 / iOS 18.5.
- Release Simulator build: **passed**, arm64 and x86_64.
- Renamed launcher: built, installed and started the isolated simulator app.
- Main/test Bundle IDs and signing settings: unchanged.
- README screenshots: exported from the renamed project's successful UI tests; synthetic records only.

Local build logs and `.xcresult` bundles are in ignored `artifacts/gramo-verification/`. Small provenance and file hashes are recorded in [rename-verification.json](evidence/rename-verification.json). The raw logs are not required to build or run the project.

## Publication boundary

The destination is `https://github.com/JJZHANG0/CONRAD_GRAMO_IOSAPP.git`, branch `main`. The previous Git remote is retained locally as `legacy-origin`.

Included: application, tests, assets, firmware source, tooling, reviewed metadata, documentation and UI screenshots. Excluded: model weights, private firmware archive, complete flash backup, signing files, credentials, scratch repositories and build products. No new blanket license was applied to existing work.
