# Contributing

## Versions

- `main` holds what is on the App Store or about to be. It is protected: changes only arrive through pull requests.
- Each version has a branch and a PR into `main`: `release/1.2.0` for a new version, `hotfix/1.0.1` (from the tag being fixed) for a fix. Branches are deleted after the merge.
- The PR template has the checklist: version and build in `project.yml` (`scripts/bump-version.sh 1.2.0`), the version's section in `CHANGELOG.md`, translations, tests on the simulator and an iPhone.
- When the build goes to the App Store, merge the PR (merge commit), then from `main`:
  1. `fastlane release`: archives, signs in the cloud, uploads with the "What's New" text from `fastlane/release_notes/<version>/` and submits for review (`fastlane release submit:false` to only upload; `fastlane beta` for TestFlight).
  2. `scripts/release.sh 1.2.0`: tags the merge commit (`v1.2.0`) and publishes a GitHub Release with the changelog notes. Version tags are protected and never move.
- fastlane needs an App Store Connect API key (Admin, for cloud signing), set in `fastlane/.env` from `fastlane/.env.example`. The key and `.env` never go into the repository.

## Building

See the README for the engine build. The engine lives outside the repository (`~/Developer/ember-engine`, linked as `engine/`) because its makefiles do not handle spaces in paths.
