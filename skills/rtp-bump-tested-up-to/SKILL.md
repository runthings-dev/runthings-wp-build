---
name: rtp-bump-tested-up-to
disable-model-invocation: true
description: Prepare a WordPress plugin patch release to update its Tested up to metadata, readmes and version fields, then publish through rtp-build after human confirmation.
---

# rtp-bump-tested-up-to

Prepare a patch release that updates WordPress tested-up-to metadata, then pause
for human review. After explicit confirmation, commit only the metadata change
and let `rtp-build` commit and publish the remaining release work.

## Inputs

- **Plugin:** An optional plugin directory path or slug. If omitted, use the
  current directory only when it is the plugin's root directory. Resolve a slug
  against the available workspace; if it does not identify exactly one plugin,
  ask for its directory. Do not choose a plugin from a parent directory containing
  several plugins.
- **WordPress version:** An optional target such as `7.1`. If omitted, resolve the
  latest stable release from the official WordPress download page or version API.
  Record the full release version and use its first two components for the
  proposed `Tested up to` value. Do not select a beta or release candidate by
  default. If the lookup fails, ask for the target.

An explicit WordPress target must be a numeric version. Preserve the requested
target branch; do not silently replace it with the latest branch. A target is an
input to preparation, not evidence that compatibility testing has passed.

## 1. Check Git readiness

Run this check in the resolved plugin directory before discovering release
details or modifying plugin files.

1. Confirm the plugin has its own Git repository and identify its root, current
   branch and configured upstream. Stop if it is merely inside another project's
   repository, has a detached HEAD or has no unambiguous upstream.
2. Inspect Git status, including staged, unstaged and untracked files. If there
   is any uncommitted work, stop and explain that the plugin is not ready for a
   bump release. Identify the files involved. Do not stash, commit, discard or
   clean anything automatically. Ignored files are not uncommitted work.
3. Fetch the configured upstream remote to establish current remote state. If
   fetching fails, stop and report that being up to date could not be verified.
4. Compare the current branch with its upstream:
   - **Equal:** Continue.
   - **Behind only:** Fast-forward to the fetched upstream with
     `git merge --ff-only @{upstream}`. Do not create a merge commit or rebase.
   - **Ahead or diverged:** Stop and report the unpublished commits or divergence.
     Do not push or reconcile branches automatically.
5. After a fast-forward, check Git status and the upstream comparison again.
   Continue only when the worktree is clean and the branch matches its upstream.
   If the fast-forward fails, stop without attempting a repair.

## 2. Discover plugin conventions

Read the plugin's build instructions and identify the files needed for the release.

### Build instructions

- Look for `BUILD.md`, `_build.md` or `build.md`, or similar in the plugin root.
- If none is present, report that the build instructions are missing. If several
  candidates exist, report the ambiguity and ask which is authoritative before
  proceeding with release preparation.
- Read the identified document and follow any explicit references needed to
  understand this plugin's build and release process.

### Readmes and version fields

- Locate the WordPress `readme.txt` and the GitHub Markdown readme, respecting
  their existing filenames and capitalization. Report missing or ambiguous files.
- Identify both changelog sections and their existing heading, date and entry
  conventions.
- Identify the upgrade-notice section in `readme.txt` and the versions it retains.
- Locate the main plugin PHP header and record its current version, the readme's
  stable tag and tested WordPress value, and the latest relevant release tag.
- Use the build instructions and source references to identify other plugin
  version fields, such as constants or package metadata. Distinguish plugin
  release versions from dependency versions; do not assume every version string
  should be bumped.
- Report conflicting version values without correcting them.

### Build and release commands

- Identify the documented checks and any compilation required before `rtp-build`.
  POT generation and packaging belong to `rtp-build` after confirmation.

## 3. Prepare the release

1. Check changes since the last release tag. A clean, synchronized repository
   can still contain unreleased functional changes. If present, stop and explain
   that they would be included in this compatibility release.
2. Before the first build, check for a running watcher; ask if its status cannot
   be established. Reuse its output and avoid duplicate builds.
3. Update `Tested up to` in `readme.txt` to the target WordPress branch. If it
   already matches, stop: no bump is needed.
4. Increment the plugin's patch version and update the applicable version
   references identified from its build instructions, including the plugin
   header, stable tag and relevant constants or package metadata. Leave
   dependency versions and minimum WordPress/PHP requirements unchanged.
5. Add the new release's changelog entry to both readmes, following their
   existing heading and date formats. Use identical description text for each
   item; only the markup differs. Describe the compatibility metadata update
   accurately, and claim successful compatibility testing only when supported
   by actual testing or the user's confirmation. Update the `readme.txt` upgrade
   notice and retain at most the latest three versions of notices.
6. Run any required compilation and relevant checks against the prepared changes.
   Stop if required checks fail.
7. Review Git status and the full diff, run `git diff --check`, and confirm that
   the changes contain only intended release preparation and generated files.
   Keep everything unstaged and uncommitted for human review.

## 4. Pause for human review

Show the prepared diff and a brief summary of the version changes and check
results. Identify any outstanding manual compatibility testing.

Ask whether to proceed with the metadata commit and `rtp-build` publication, then
wait for explicit confirmation. Keep all changes unstaged and uncommitted until
confirmed.

## 5. On confirmation, commit metadata and publish

1. Check that the remaining changes are the reviewed release preparation.
   `rtp-build` stages all remaining changes with `git add -A`.
2. Stage only the `Tested up to` metadata change. The same readme also contains
   the stable-tag, changelog and upgrade-notice changes, so stage the exact
   metadata line. Inspect the staged diff to verify that nothing else is included.
3. Commit that staged change as:

   ```text
   docs(meta): bump tested up to X.X
   ```

   Replace `X.X` with the target WordPress branch. Leave all other preparation
   changes uncommitted.
4. Run `rtp-build` from the plugin root with the remaining preparation changes
   uncommitted. It generates the POT and package, commits all remaining changes
   as `chore(release): deploy vX.Y.Z`, tags that commit and pushes.
5. Report the command result. If it fails, stop and identify the failed step.
