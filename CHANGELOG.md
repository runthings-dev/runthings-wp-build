# Changelog

## 3.1.0
- Added interactive prompt to create `.distignore` if missing
- Moved `.distignore` template to external file for easier maintenance

## 3.0.0
- Added `--init` option to scaffold `.distignore`
- Added `--force` option to overwrite existing releases or `.distignore`
- Added early abort if release version already exists
- Added colored terminal output with `NO_COLOR` support
- Added automatic git commit, tag, and push on build
- Added `RTP_RELEASE_DIR` environment variable support for release archive directory

