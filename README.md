# iroha-demo-point

Modernized Hyperledger Iroha (v2+) demo wallet that now talks directly to Torii using
the latest Swift SDK from the sibling [`iroha`](../iroha) monorepo.

## Requirements

- Xcode 17 / iOS 26 SDK
- `pod` (CocoaPods 1.16+)
- Local checkout of `../iroha` (the bleeding-edge Iroha repo)

## Bootstrap

1. Ensure the sibling repo `../iroha` exists (for example: `/Users/you/dev/iroha`).
2. Copy the native `NoritoBridge` XCFramework into this repo (needed for signing):

   ```bash
   ./scripts/bootstrap_norito.sh
   ```

   The script copies `../iroha/dist/NoritoBridge.xcframework` into `Vendor/NoritoBridge`.
3. Install CocoaPods dependencies (includes the local `IrohaSwift` pod):

   ```bash
   cd Example-Point
   pod install --repo-update
   ```

4. Open `Example-Point/Example-Point.xcworkspace` in Xcode.

## Configuration

`Example-Point/Info.plist` exposes the Torii connection details:

| Key                    | Description                                             |
|------------------------|---------------------------------------------------------|
| `ToriiBaseURL`         | Base REST endpoint (e.g. `https://127.0.0.1:8080`)       |
| `ToriiChainId`         | Chain identifier used when building transactions        |
| `ToriiAssetDefinitionId` | Asset to display and transfer (`asset#domain`)        |
| `ToriiDefaultDomain`   | Legacy compatibility key; canonical account IDs are i105 |
| `Unit`                 | Display unit string shown in the wallet UI              |

Update these values to point at your Torii node before running the app.

## Running the app

1. Launch the workspace in Xcode.
2. Choose the `Example-Point` scheme and your preferred simulator/device.
3. Build & run. On first launch the SORA Nexus onboarding screen lets you generate a
   new key pair (12 or 24 word passphrase), back it up manually/iCloud/Google Secure
   Storage, or link an existing SORA Nexus account via IrohaConnect before the app
   calls Torii’s `/v1/accounts/onboard` endpoint.
4. Use the **Wallet**, **Send**, and **Receive** tabs to interact with Torii.

Account identity rules are strict:

- Canonical account IDs are always i105 literals.
- Human-facing aliases must use `name@dataspace` or `name@domain.dataspace`.
- Aliases are resolved on-chain to canonical i105 account IDs before transfers/signing.

### Key backup & IrohaConnect

- The onboarding card exposes a 12-word (128-bit) or 24-word (256-bit) passphrase.
- “手動でバックアップ” triggers the iOS share sheet so users can copy or print the
  phrase immediately; the “保存” buttons push the phrase to iCloud key-value storage
  or the Google secure keychain bucket bundled with the app.
- Selecting “IrohaConnectで連携” launches the companion app (if installed) and
  accepts a callback URL with the existing key material. The wallet verifies that the
  returned public/private keys match before saving them locally.

## Typography

- The app bundles the [Sora v2.1 beta fonts](https://github.com/sora-xor/sora-font/tree/master/fonts/ttf/v2.1beta)
  inside `Example-Point/Example-Point/Fonts/Sora` and registers them via `UIAppFonts`.
- Use the `UIFont.sora(_:size:italic:)` helper in `SoraFont.swift` whenever you need a
  specific weight, and call `applySoraFonts()` inside new view controllers so every label,
  text field, and button automatically swaps system fonts for Sora at runtime.
- Switch between System, Light, and Dark appearances via the paintbrush button on the
  Wallet screen; it presents `ThemeSettingsViewController`, which persists your choice.

## Visual flair

- A lightweight `SakuraEmitterView` now paints falling petals across every glassmorphic
  screen. The emitter responds to device tilt via Core Motion so the flowers drift as the
  user moves their phone. Extend or reuse this effect via `installGlassBackground()`.

## Validation

- Run `./scripts/lint_storyboards.sh` (called from CI) to ensure Interface Builder outlet
  connections stay in sync after storyboard edits. The script re-compiles every storyboard
  with `ibtool --compile`, failing fast when an outlet or asset reference is missing.
- Execute `xcodebuild -workspace Example-Point/Example-Point.xcworkspace -scheme Example-Point -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.1' CODE_SIGNING_ALLOWED=NO test`
  to build and run the unit/UI test suites.

## Notes

- `NoritoBridge.xcframework` is large and therefore ignored in git. Run the bootstrap
  script whenever you update the bridge inside the `iroha` repo.
- The demo fetches balances and transaction summaries directly from Torii and submits
  transfers via the pipeline endpoints using `IrohaSwift`.

## Torii onboarding

`/v1/accounts/onboard` requires Torii to have a registrar authority/key configured.
Add the following snippet to your Torii config (see `iroha_config` docs for location):

```toml
[torii.onboarding]
enabled = true
authority = "registrar@wonderland"
private_key = "ed25519:0120..."
# optional: restrict new accounts to a specific domain
# allowed_domain = "wonderland"
```

The iOS app sends basic device metadata (`platform`, `system_version`, `locale`, etc.)
as the onboarding `identity` payload and registers the resulting account id with
`RegisterAccount` on the chain.
