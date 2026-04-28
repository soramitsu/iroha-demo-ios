## Repository Guide for Agents

### Layout
- `Example-Point/` — iOS demo wallet target. Always open `Example-Point.xcworkspace` after running `pod install`.
- `Vendor/NoritoBridge/` — checked-in XCFramework + podspec. `scripts/bootstrap_norito.sh` refreshes it from `../iroha/dist`.
- `scripts/` — helper scripts (currently just the Norito bootstrapper).

### Expectations
1. **Swift & SwiftPM**: The project is Swift 6 with UIKit. Prefer async/await and modern APIs (AVFoundation, etc.).
2. **Pods**: Dependencies come via CocoaPods from the sibling `../iroha` checkout. Any change to `IrohaSwift` or `NoritoBridge` requires re-running `pod install`.
3. **Design system**: UI sticks to the refreshed glassmorphic kit (`GlassmorphicStyle.swift`). Reuse those helpers instead of custom blurs.
4. **Torii backend**: Backends live in `../iroha`. If the app needs new API surface, add it there (Torii service, IrohaSwift) and wire through the pods.
5. **Testing**: When you add a new function—whether in app code or upstream pods—add at least one unit test covering it. Use multiple tests for complex logic or branches. Tests live in the appropriate `Tests/` target (or the `iroha` repo for pod changes); wire them into `xcodebuild test` as part of your validation.
6. **Build/testing**:
   ```bash
   cd Example-Point
   pod install
   xcodebuild -workspace Example-Point.xcworkspace \
              -scheme Example-Point \
              -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.1' \
              CODE_SIGNING_ALLOWED=NO build
   ```
   Always target iOS 26+ simulators.

### Coordination with `iroha`
- Keep this repo and `/Users/.../iroha` in sync. The pods reference that sibling path.
- Large features need Torii + IrohaSwift updates upstream, then `pod install` here.

### When adding features
- Update Keychain handling via `KeychainSession`.
- Use `ToriiService` as the single Torii entry point; add methods there when hitting new endpoints.
- Maintain localized strings (existing ones are Japanese).
- Typography must use the bundled Sora v2.1beta fonts—reach for the helpers in
  `SoraFont.swift` (`UIFont.sora` / `applySoraFonts()`) instead of `UIFont.system`.
- Every screen leverages the motion-reactive sakura emitter via `installGlassBackground()`;
  keep that call in new controllers to retain the animated effect.
- Leave the appearance selector accessible (paintbrush button on Wallet); new flows should
  respect `ThemeManager` overrides when presenting content.
- First-launch onboarding now lives in `SoraNexusOnboardingViewController` and must
  support 12/24 word mnemonic generation, manual/iCloud/Google backups, and
  IrohaConnect linking—keep new onboarding UX within that flow.

### Troubleshooting
- Build failure mentioning new Torii APIs? Ensure the matching Swift types exist in `IrohaSwift` under `../iroha` and reinstall pods.
- “Supported platforms empty” from Xcode: target a specific simulator (see build command above).

Keep this file updated when major workflows or tooling change.
