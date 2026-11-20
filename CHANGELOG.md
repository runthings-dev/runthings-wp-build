# Changelog

## 4.0.0 - 20th November 2026
- Added `--tested-up-to <version>` to generate a clipboard prompt for bulk WordPress compatibility releases using a plugin list from `RTP_PLUGINS_JSON_URL`
- Added the `rtp-bump-tested-up-to` agent skill to prepare and publish compatibility patch releases, including from clean branches with unpublished commits
- Added `-h` and `--help` to show command usage
- Synced `package.json` and existing npm lockfiles to the plugin header version during local and release builds
- Enabled Git release commits, tags, and pushes when `RTP_RELEASE_DIR` is unset
- Allowed `--init` and workflow installation in the same command and added errors for incompatible action combinations
- Added targeted update commands for outdated workflows, fixed `.github/` exclusions in `.distignore` on Linux, and made workflow installation failures return an error
- Made release commands report which step failed when creating a tag or pushing the commit or tags
- Updated the changelog prompt to clarify it should be identical entry wording in the WordPress and GitHub readmes

## 3.5.0 - 31st October 2026
- Fixed plugin ZIPs to include a top-level plugin folder, preventing renamed ZIP files from installing a second copy instead of replacing the existing plugin

## 3.4.0 - 16th May 2026
- Fixed version extraction would break if plugin meta started with `/*` instead of `/**`
- Fixed version extraction would break if plugin meta was not in first comment block
- Added `--local` option to test build without git deploy
- Updated changelog prompt

## 3.3.0 - 7th February 2026
- Added `--workflows` option to deploy workflow templates
- Added `--workflows:<name>` option to deploy specific workflow templates

## 3.2.0 - 6th January 2026
- Added `--changelog` option to generate changelog prompt from commits since last tag
- Added Linux clipboard support (`xclip`, `xsel`) alongside macOS `pbcopy`
- Added `git` to required tools check

## 3.1.0 - 5th January 2026
- Added interactive prompt to create `.distignore` if missing
- Moved `.distignore` template to external file for easier maintenance

## 3.0.0 - 4th January 2026
- Added `--init` option to scaffold `.distignore`
- Added `--force` option to overwrite existing releases or `.distignore`
- Added early abort if release version already exists
- Added colored terminal output with `NO_COLOR` support
- Added automatic git commit, tag, and push on build
- Added `RTP_RELEASE_DIR` environment variable support for release archive directory

