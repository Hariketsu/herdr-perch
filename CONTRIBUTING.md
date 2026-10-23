# Contributing

Thanks for helping with Herdr Perch. Bug reports, ideas and pull requests are all welcome.

## Before you start

- Read [ARCHITECTURE.md](ARCHITECTURE.md) for a map of the code and the rules it relies on.
- Search the [issues](https://github.com/Hariketsu/herdr-perch/issues), open and closed, before filing a new one.
- For anything larger than a small fix, open an issue first so we can agree on the approach before you write the code.

## Reporting bugs

Use the bug report form. Include the versions of Perch (shown in the About window), macOS and Herdr (`herdr --version`), and which display Perch is on. Screenshots and recordings help, but hide agent titles and project names you don't want to share before attaching them.

## Development setup

You need macOS 14 or later, Xcode 16 or later (Swift 6), and [Herdr](https://github.com/herdrdev/herdr) 0.9.5 or later for anything beyond the unit tests.

```sh
swift build
swift test                       # unit tests, no Herdr needed
scripts/bundle.sh                # builds dist/Herdr Perch.app
open "dist/Herdr Perch.app"
```

Quit any running copy of Perch first; two copies would both draw in the notch. `perchctl dump` and `perchctl watch` print the state Perch derives from Herdr, and launching the app with `PERCH_TRACE=<file>` writes the same rows to a file as they change.

## Tests

- **Unit tests** (`swift test`) must pass for every pull request. New logic in `PerchCore` or `PerchApp/Presentation` should come with tests; both are designed to be tested without a window or a running Herdr.
- **End-to-end tests** (`uv run --project Tests/E2E pytest Tests/E2E -p no:cacheprovider`) start a throwaway Herdr session named `perch-e2e`, drive agent states in it, and delete it afterwards. They never write to your other sessions.
- **`scripts/smoke.sh`** builds and launches the app against your default Herdr session, read-only.
- **`scripts/perf.sh`** measures CPU. It moves the pointer and needs Accessibility permission for your terminal; `--static` avoids pointer movement.

## Guidelines

- Match the style of the surrounding code, and keep each change focused on one thing.
- Perch is read-only toward Herdr. The only call that changes anything is focusing a pane after the user clicks a row. Don't add hooks, CLI calls or background processes.
- **Use fictional data only.** The repository is public: tests, fixtures, screenshots and docs must never contain real agent titles, project names or local paths.
- When you change behaviour or settings, update [ARCHITECTURE.md](ARCHITECTURE.md) if it describes them, and both [README.md](README.md) and [README.zh-CN.md](README.zh-CN.md). If you can't write the Chinese part, say so in the pull request and it will be done for you.
- Commit messages are in English and follow [Conventional Commits](https://www.conventionalcommits.org/), for example `fix(app): keep the notch inside the menu bar`.

## Pull requests

Fill in the pull request template, link the issue it addresses, and make sure CI passes. One topic per pull request makes review faster.

Releases are made by the maintainer; the steps are in [AGENTS.md](AGENTS.md).

## License

By contributing, you agree that your contributions are licensed under the [GPL-3.0](LICENSE), the license of this project.
