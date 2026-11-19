# runthings-wp-build

Build distribution-ready WordPress plugin ZIPs on macOS and Linux. `rtp-build` can build a ZIP locally or commit, tag, and push a release. It was originally built for [runthings.dev](https://runthings.dev/) plugins.

## Getting started

### Requirements

- npm to install `rtp-build`.
- Git, `rsync`, `zip`, `mktemp`, and WP-CLI (`wp`) on your `PATH` to build a plugin.
- Composer on your `PATH` if the plugin has a `vendor/autoload.php` file.

### Installation

```bash
npm install -g runthings-wp-build
```

### Build your first ZIP

1. Open the root directory of your WordPress plugin. Its main PHP file must match the directory name, for example `my-plugin/my-plugin.php`.
2. If the plugin has no `.distignore` file, run `rtp-build --init`. Review [`.distignore`](#distignore) before building to make sure the ZIP includes the files your plugin needs.
3. Run `rtp-build --local` to generate the translation `.pot` file and ZIP while skipping release archiving and Git commit, tag, and push operations.

Both local builds and releases regenerate the Composer autoloader if `vendor/autoload.php` exists. When the plugin has a `package.json`, they use npm to sync it and any existing npm lock files to the plugin header version without running npm lifecycle scripts or creating an npm commit or tag.

### Output

The ZIP is written to `build/{plugin-slug}.zip`. It contains one top-level `{plugin-slug}/` folder with the main PHP file inside. This keeps the installed folder name stable when the ZIP filename changes. To replace an existing installation, use the same slug as its installed folder. [WordPress ZIP installation behavior](https://developer.wordpress.org/reference/classes/wp_upgrader/install_package/)

## Releasing a version

Plain `rtp-build` builds the plugin, stages all pending changes with `git add -A`, commits them as `chore(release): deploy v{version}`, creates the tag `v{version}`, and pushes the commit and tags to the Git remote. Review your working tree before running it.

1. Commit changelog and upgrade notice changes first, for example `docs(readme): changelog for v{version}`.
2. Update the version in the plugin header, the stable tag in `readme.txt`, and any plugin version constants. Leave those changes uncommitted for the release command.
3. Run `rtp-build` from the plugin root.

### Release archives

Set `RTP_RELEASE_DIR` to archive a copy of each release ZIP at `{RTP_RELEASE_DIR}/{plugin-slug}/releases/v{version}/{plugin-slug}.zip`. You can export it in your shell startup file for repeated use. When it is unset, the command skips archiving.

### Automation

For CI/CD automation such as GitHub Releases or WordPress.org deployment, use the tag push as the trigger. See [Workflow setup](#workflow-setup) for the bundled GitHub Actions templates.

## Reference

### Options

Run `rtp-build --help` from any directory to see usage. Run setup commands, local builds, and each of the [prompt commands](#prompts) in separate invocations.

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

### .distignore

Use `.distignore` in the plugin root to exclude files from the ZIP. The example below shows common exclusions in rsync syntax.

```gitignore
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

### Prompts

| Option | Description |
|--------|-------------|
| `--changelog` | Generate a changelog prompt from the current repository’s Git history. |
| `--tested-up-to <version>` | Generate a bulk prompt targeting the supplied WordPress version. Requires `RTP_PLUGINS_JSON_URL`. |

#### Changelog

Run from the plugin’s Git repository to generate a changelog prompt from commits since the latest tag. If there are no tags, the command uses up to 20 recent commits. It copies the prompt to the clipboard using `pbcopy`, `xclip`, or `xsel` when available and prints it otherwise.

```bash
rtp-build --changelog
```

#### Tested up to

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

The command requires `curl` and `jq`. It uses `pbcopy`, `xclip`, or `xsel` for clipboard support. If copying is unavailable or fails, the prompt is printed instead. Fetch or validation failures leave the clipboard untouched. Paste the generated prompt into your agent session to start the skill's release flow.

## Author

Matthew Harris @ [runthings.dev](https://runthings.dev/)

## Repository

[github.com/runthings-dev/runthings-wp-build](https://github.com/runthings-dev/runthings-wp-build)

## License

MIT

