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

Builds require a main plugin file named `{plugin-slug}.php` (matching the directory name). Run `rtp-build --help` from any directory to see the available commands.

## Options

| Option | Description |
|--------|-------------|
| `--local` | Generate the POT and ZIP locally. Skip release archiving and Git commit, tag, and push operations. |
| `--init` | Create a default `.distignore` file in the current directory |
| `--workflows` | Deploy all bundled GitHub Actions workflows to `.github/workflows/` |
| `--workflows:<name>` | Deploy one bundled workflow (`release` or `wporg`). Repeat the option to select multiple workflows. |
| `-f`, `--force` | Allow replacing an existing release archive, replacing `.distignore` during init, or overwriting unmanaged or outdated workflows during workflow deployment. Also allow builds with outdated workflows. |
| `-h`, `--help` | Show command-line usage and options |

### Workflow setup

Combine `--init` with `--workflows` or `--workflows:<name>` to create `.distignore` first and then deploy the selected workflows. Use `--force` when you want to replace an existing `.distignore` or update an unmanaged or outdated workflow. Workflow deployment always preserves workflows marked `-custom` and managed workflows that already match the template version.

```bash
rtp-build --init --workflows
rtp-build --workflows:release --force
```

Run setup commands, local builds, changelog prompts, and Tested up to prompts in separate invocations.

## Prompts

| Option | Description |
|--------|-------------|
| `--changelog` | Generate a changelog prompt from the current repository’s Git history. |
| `--tested-up-to <version>` | Generate a bulk prompt targeting the supplied WordPress version. Requires `RTP_PLUGINS_JSON_URL`. |

### Changelog

Run from the plugin’s Git repository to generate a changelog prompt from commits since the latest tag. If there are no tags, the command uses up to 20 recent commits. It copies the prompt to the clipboard when a clipboard tool is available and prints it otherwise.

```bash
rtp-build --changelog
```

### Tested up to

Set `RTP_PLUGINS_JSON_URL` to the direct URL of a JSON file containing your WordPress plugin slugs. The command can run from any directory.

```bash
RTP_PLUGINS_JSON_URL="https://example.com/plugins.json" rtp-build --tested-up-to 7.1
```

To use the same list in every shell session, add `export RTP_PLUGINS_JSON_URL="https://example.com/plugins.json"` to your shell startup file, such as `~/.zshrc` for interactive Zsh sessions. You can then run `rtp-build --tested-up-to 7.1` directly.

The file must contain a non-empty JSON array of slug strings. Use lowercase letters and numbers, with single hyphens between parts of a slug.

```json
[
  "my-first-plugin",
  "my-second-plugin"
]
```

The command inserts the fetched slugs into a prompt targeting the supplied WordPress version. The prompt requests one sub-agent per plugin, the skill's full release flow, continued progress if a plugin is blocked, decisions surfaced in the parent thread, parent handling of elevated commands, and a consolidated results table.

This option only generates the prompt; it does not run the skill or perform build or release operations. Paste the prompt into your agent session to begin. It requires `curl` and `jq`, plus `pbcopy`, `xclip`, or `xsel` for clipboard support. If copying is unavailable or fails, the prompt is printed instead. Fetch or validation failures leave the clipboard untouched.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `RTP_RELEASE_DIR` | No | Base directory for versioned release archives. When set, copies the zip to `{RTP_RELEASE_DIR}/{plugin-slug}/releases/v{version}/`. When unset, skips archiving. |
| `RTP_PLUGINS_JSON_URL` | Only for `--tested-up-to` | Direct URL to a JSON array of plugin slugs. Has no default. |

## Requirements

The following tools must be installed and available in your PATH:

- `git`
- `rsync`
- `zip`
- `mktemp`
- `wp` (WP-CLI)
- `npm` (only if your plugin has a `package.json`)
- `composer` (optional, only if your plugin uses Composer)
- `curl` and `jq` (only for `--tested-up-to`)
- `pbcopy`, `xclip`, or `xsel` (optional, for `--changelog` and `--tested-up-to` clipboard support)

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

