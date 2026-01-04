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

