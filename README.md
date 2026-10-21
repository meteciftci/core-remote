# CoreRemote

A macOS 26+ app for saving SSH and RDP connections and opening them with a double-click.

- **SSH** opens in Terminal. A saved password is kept in the Keychain and handed to `ssh` through `SSH_ASKPASS` (a one-time `0600` file that the helper deletes on first read). New host keys are accepted automatically (`StrictHostKeyChecking=accept-new`); changed keys are still rejected.
- **RDP** opens in [Microsoft Windows App](https://apps.apple.com/app/id1295203466) (`brew install --cask windows-app`) via a generated `.rdp` file. The saved password is copied to the clipboard and cleared after 30 seconds.
- **Backup**: export and import `.coreremote` files. Passwords are only included when the file is encrypted with a passphrase (AES-GCM, PBKDF2-SHA256).

## Build

Requires Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open CoreRemote.xcodeproj
```

`CoreRemote.xcodeproj` is generated from `project.yml` and is not checked in.

Run the tests from the command line:

```bash
xcodebuild -project CoreRemote.xcodeproj -scheme CoreRemote test
```
