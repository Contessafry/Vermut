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

## Code of conduct

Be respectful. No harassment, personal attacks, or trolling.

## Licence

Contributions are accepted under the MIT licence in `LICENSE`.
