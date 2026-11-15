<!-- One PR per version or hotfix: release/x.y.z or hotfix/x.y.z into main. -->

## Version

<!-- e.g. 1.2.0 (build 4) -->

## What changed

<!-- The same items as this version's section in CHANGELOG.md. -->

## Checklist

- [ ] `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` bumped (`scripts/bump-version.sh`)
- [ ] `CHANGELOG.md` has this version's section
- [ ] `scripts/check.sh` passes (also runs on the PR)
- [ ] `EmberTests` pass on the simulator
- [ ] New strings translated (English and Spanish)
- [ ] Built and played on the simulator; installed on a real iPhone
- [ ] iPhone Duo checked, if layouts changed

## After merge

- [ ] Uploaded to App Store Connect from the merge commit
- [ ] `scripts/release.sh x.y.z` (annotated tag and GitHub Release)
