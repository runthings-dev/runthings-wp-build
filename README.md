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

- `rsync`
- `zip`
- `mktemp`
- `wp` (WP-CLI)
- `composer` (optional, only if your plugin uses Composer)

## What It Does

1. **Regenerates Composer autoloader** (if `vendor/autoload.php` exists)
2. **Generates `.pot` translation file** using WP-CLI with sensible excludes
3. **Creates clean zip** excluding development files via `.distignore`
4. **Archives release** to versioned directory (if `RTP_RELEASE_DIR` is set)
5. **Commits, tags, and pushes** the release to git remote

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

2. **Update version numbers** - update all version references (plugin header, readme.txt stable tag, version constants/defines) to the new version. **Leave these changes uncommitted.**

3. **Run the build:**
   ```bash
   rtp-build
   ```

   This will:
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

## Author

Matthew Harris @ [runthings.dev](https://runthings.dev/)

## Repository

[github.com/runthings-dev/runthings-wp-build](https://github.com/runthings-dev/runthings-wp-build)

## License

MIT

