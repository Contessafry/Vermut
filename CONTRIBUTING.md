# Contributing to Vermut

Thanks for helping. Vermut is a native macOS app: SwiftUI on top of a testable core library.

## Bugs

1. Search [existing issues](https://github.com/Contessafry/Vermut/issues).
2. Open a new issue with:
   - macOS version and Apple Silicon chip
   - Vermut version (`v` in the sidebar)
   - Steps to reproduce
   - Expected vs actual
   - Output of **Settings → Copy diagnostic report** (paths and emails are redacted)

## Pull requests

```bash
git clone https://github.com/YOUR_USERNAME/Vermut.git
cd Vermut
swift test
```

On a Mac, `./build.sh` also produces `Vermut.app`.

- Keep product copy as **Vermut**. Swift package targets may stay `CaskLauncherCore` / `CaskLauncherApp`.
- Do not show `grapple` in UI strings. The engine picker must say **Vermut Wine**. Internal ids such as `grapple-wine` are fine.
- Put business logic in `Sources/CaskLauncherCore` with a unit test. Keep SwiftUI in `Sources/CaskLauncherApp`.
- Do not change Steam’s launch recipe unless you re-tested Steam on a Mac.
- Epic Games goes through Legendary. Do not reintroduce the Windows Epic Games Launcher.
- Run `swift test` (Linux Swift 6 is enough for core). On a Mac, also launch `Vermut.app`.

## Publishing a beta release

The in-app updater’s **Beta** channel reads GitHub Releases with `prerelease: true`.

1. Bump nothing in `main` unless you intend to ship — betas use a pre-release tag only.
2. Tag: `vX.Y.Z-beta.N` (SemVer pre-release), e.g. `v1.2.0-beta.1`.
3. On GitHub → Releases → Draft a new release → choose that tag.
4. Check **Set as a pre-release**. Leave “latest release” unchecked.
5. Publish. Stable-channel users keep using `/releases/latest`; Beta users get the highest SemVer including pre-releases.

When the beta is ready for everyone, publish `vX.Y.Z` as a normal (non–pre-release) release.

## Code of conduct

Be respectful. No harassment, personal attacks, or trolling.

## Licence

Contributions are accepted under the MIT licence in `LICENSE`.
