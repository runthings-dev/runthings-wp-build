# runthings-wp-build

Build distribution-ready WordPress plugin zip files.

A simple build tool for WordPress plugins. Originally built for [runthings.dev](https://runthings.dev/) plugins, but works with any plugin following standard WP conventions.

## Installation

```bash
npm install -g runthings-wp-build
```

## Usage

Run from the root directory of your WordPress plugin:

```bash
rtp-build [options]
```

The plugin directory must contain a main plugin file named `{plugin-slug}.php` (matching the directory name).

## Options

| Option | Description |
|--------|-------------|
| `--init` | Create a default `.distignore` file in the current directory |
| `--changelog` | Generate a changelog prompt from commits since last tag and copy to clipboard |
| `-f`, `--force` | Overwrite existing release archive (or `.distignore` with `--init`) |

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `RTP_RELEASE_DIR` | No | Base directory for versioned release archives. When set, copies the zip to `{RTP_RELEASE_DIR}/{plugin-slug}/releases/v{version}/` |

## Requirements

The following tools must be installed and available in your PATH:

- `git`
- `rsync`
- `zip`
- `mktemp`
- `wp` (WP-CLI)
- `npm` (only if your plugin has a `package.json`)
- `composer` (optional, only if your plugin uses Composer)
- `pbcopy`, `xclip`, or `xsel` (optional, for `--changelog` clipboard support)

## What It Does

1. **Syncs npm package versions** to the main plugin header (if `package.json` exists), updating `package.json` and existing npm lock files without running npm lifecycle scripts or creating an npm commit or tag
2. **Regenerates Composer autoloader** (if `vendor/autoload.php` exists)
3. **Generates `.pot` translation file** using WP-CLI with sensible excludes
4. **Creates clean zip** excluding development files via `.distignore`
5. **Archives release** to versioned directory (if `RTP_RELEASE_DIR` is set)
6. **Commits, tags, and pushes** the release to git remote

## Workflow

### Initial Setup

1. Install globally:
   ```bash
   npm install -g runthings-wp-build
   ```

2. In your plugin directory, create the `.distignore` file:
   ```bash
   rtp-build --init
   ```

3. Review and customise `.distignore` for your project.

### Releasing a Version

1. **Commit your changelog** - commit any changelog and upgrade notice changes first, as `docs(readme): changelog for v{version}`

2. **Update version numbers** - update the plugin header, readme.txt stable tag, and version constants/defines to the new version. `rtp-build` syncs `package.json` and existing npm lock files from the plugin header automatically, including in `--local` mode. **Leave these changes uncommitted.**

3. **Run the build:**
   ```bash
   rtp-build
   ```

   This will:
   - Sync npm package versions using `npm version "$VERSION" --no-git-tag-version --ignore-scripts --allow-same-version`
   - Generate the `.pot` file
   - Create the distribution zip
   - Commit all uncommitted changes with message `chore(release): deploy v{version}`
   - Create a git tag `v{version}`
   - Push the commit and tag to remote

### Automation

If you have CI/CD automations (e.g., creating GitHub releases, deploying to WordPress.org), trigger them from the tag push event.

## .distignore

Create a `.distignore` file in your plugin root to specify files/directories to exclude from the build. Uses rsync exclude syntax.

Example:
```
# Ignore development files
.wordpress-org/
.git/
node_modules/
vendor/
tests/
build/
.distignore
.gitignore

# Ignore configuration files
*.yml
*.lock

# Ignore build scripts and macOS file system files
/bin/
.DS_Store
__MACOSX
```

## Output

- `build/{plugin-slug}.zip` - The distribution-ready zip file
- `{RTP_RELEASE_DIR}/{plugin-slug}/releases/v{version}/{plugin-slug}.zip` - Archived release (optional)

The ZIP contains a single top-level `{plugin-slug}/` folder, with the main plugin file at `{plugin-slug}/{plugin-slug}.php`. The slug comes from the project directory name and must match the existing installation's folder name for WordPress to offer replacement when uploading the ZIP.

This keeps the installation folder stable even if the ZIP filename changes (for example, a download adds `-1`). With files at the ZIP root, [WordPress derives the installation folder from the ZIP filename](https://developer.wordpress.org/reference/classes/wp_upgrader/install_package/), which can cause a separate installation instead of replacing the existing plugin.

## Author

Matthew Harris @ [runthings.dev](https://runthings.dev/)

## Repository

[github.com/runthings-dev/runthings-wp-build](https://github.com/runthings-dev/runthings-wp-build)

## License

MIT

