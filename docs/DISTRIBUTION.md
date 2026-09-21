# Distribution

Glosso is shared with a small group without an Apple Developer Program account, so it is **not notarized**. It is signed with a **stable self-signed certificate** instead. That stability is load-bearing: macOS pins the Accessibility (TCC) grant to the signing identity, so reusing the same certificate for every release keeps the permission across updates. An ad-hoc signature changes per build and would force every user to re-grant Accessibility on each update.

## One-time setup (maintainer)

### 1. Create the signing certificate

Keychain Access → **Certificate Assistant → Create a Certificate**:

- Name: `Glosso Self-Signed` (must match `CODE_SIGN_IDENTITY` in `project.yml`)
- Identity Type: **Self-Signed Root**
- Certificate Type: **Code Signing**
- Optionally override defaults to set a long validity (e.g. 3650 days)

Trust it for signing: double-click the certificate → **Trust → Code Signing: Always Trust**. Verify:

```bash
security find-identity -v -p codesigning   # must list "Glosso Self-Signed"
```

> After first building with this certificate, the old TCC grant (from the previous identity) is stale. Reset and re-grant once:
> ```bash
> tccutil reset Accessibility com.mirek.glosso
> ```

## Cutting a release

There are no GitHub Actions workflows. Merging a PR does not build, review, tag, or publish a release.

1. Bump `MARKETING_VERSION` in `project.yml` in the release PR and run the local offline tests.
2. After merging, check out the intended release commit and build with the stable signing certificate:
   `CI=1 scripts/package.sh`. The existing `CI=1` switch skips installation and launching on the maintainer's Mac.
3. Create a GitHub Release manually with tag `v<MARKETING_VERSION>` targeting that commit, and attach `.build/release/Glosso.zip`.
4. Update any pinned download links in `docs/index.html` and `docs/en/index.html` to the published tag.
5. Verify that the in-app update check points to the new release.

Signing material stays in the maintainer's Keychain. The `.p12`/`.pem`/`.cer` files remain git-ignored; never commit them.

The repository must be **public** so the unauthenticated GitHub API (`releases/latest`) and the release asset download work for everyone.

## Install instructions (for users — paste into release notes)

1. Download `Glosso.zip` and unzip it.
2. Drag **Glosso.app** to your **Applications** folder.
3. The first launch is blocked because the app is signed but not notarized by Apple. On macOS 15 (Sequoia) and later the old right-click → **Open** trick no longer works — instead click **Done**, then open **System Settings → Privacy & Security**, scroll to the bottom, and click **Open Anyway** next to the Glosso message. Needed once.
   - Shortcut from a terminal: `xattr -dr com.apple.quarantine /Applications/Glosso.app` clears the download-quarantine flag so it opens normally.
4. Click the Glosso icon in the menu bar and grant **Accessibility** when asked.
5. The setup wizard guides you through choosing a model and language.

Updates: when the menu shows a new version, download it and drag it over the old one. You will **not** need to grant Accessibility again.
