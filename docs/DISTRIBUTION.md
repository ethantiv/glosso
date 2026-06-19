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

### 2. Add CI secrets

Export the certificate **with its private key** to a `.p12` (Keychain Access → select the cert + key → Export → `.p12`, set a password). Then in the GitHub repo, add **Settings → Secrets and variables → Actions**:

- `SIGNING_CERT_P12_BASE64` — `base64 -i cert.p12 | pbcopy`
- `SIGNING_CERT_PASSWORD` — the `.p12` password

The `.p12`/`.pem`/`.cer` files are git-ignored; never commit them.

## Cutting a release

1. Bump `MARKETING_VERSION` in `project.yml` (e.g. `0.2.0`).
2. Commit, then tag and push — the tag must match the version, prefixed with `v`:
   ```bash
   git tag v0.2.0
   git push --tags
   ```
3. The `Release` workflow builds, signs, and publishes `Glosso.zip` to a GitHub Release.
4. The in-app update check (menu bar → "Dostępna nowa wersja …") points users at the release page.

The repository must be **public** so the unauthenticated GitHub API (`releases/latest`) and the release asset download work for everyone.

## Install instructions (for users — paste into release notes)

1. Download `Glosso.zip` and unzip it.
2. Drag **Glosso.app** to your **Applications** folder.
3. Right-click Glosso.app → **Open** → confirm **Open** (needed once, because the app is not from the App Store).
4. Click the Glosso icon in the menu bar and grant **Accessibility** when asked.
5. The setup wizard guides you through choosing a model and language.

Updates: when the menu shows a new version, download it and drag it over the old one. You will **not** need to grant Accessibility again.
