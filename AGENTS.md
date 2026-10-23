# AGENTS.md

## Commits

Write commit messages in English, as Conventional Commits: `fix(app): keep the notch inside the menu bar`, with the reason in the body.

## Release

Ask the user before every push.

1. Set `CFBundleShortVersionString` and `CFBundleVersion` (build number, +1) in `scripts/bundle.sh` (0.x: new features bump the minor version, fixes the patch version). Commit as `chore(release): bump version to X.Y.Z`.
2. `git push origin main` and wait for CI to pass: `gh run watch <id> --exit-status`.
3. Only then tag and push the tag: `git tag -a vX.Y.Z -m "Herdr Perch X.Y.Z" -m "- **Change** — one sentence." && git push origin vX.Y.Z`. The first line becomes the Release title, the rest its "What's new" list. Write it in English, and no lines starting with `#` (git strips them).
4. Watch the Release workflow. It runs the unit tests, checks that the tag matches `scripts/bundle.sh`, builds `Herdr-Perch-X.Y.Z.dmg`, and creates the GitHub Release. Confirm with `gh release view vX.Y.Z`.

Tag last: a published Release is harder to take back than a red CI run. To release a tag that is already pushed, run `gh workflow run release.yml -f tag=vX.Y.Z`.
