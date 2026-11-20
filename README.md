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
4. If you plan to publish through GitHub Actions, follow [Workflow setup](#workflow-setup) before your first release.

Both local builds and releases regenerate the Composer autoloader if `vendor/autoload.php` exists. When the plugin has a `package.json`, they use npm to sync it and any existing npm lock files to the plugin header version without running npm lifecycle scripts or creating an npm commit or tag.

### Output

The ZIP is written to `build/{plugin-slug}.zip`. It contains one top-level `{plugin-slug}/` folder with the main PHP file inside. This keeps the installed folder name stable when the ZIP filename changes. To replace an existing installation, use the same slug as its installed folder. [WordPress ZIP installation behavior](https://developer.wordpress.org/reference/classes/wp_upgrader/install_package/)

### Workflow setup

For a plugin hosted on GitHub, install the workflows you want during initial setup, before pushing the first release tag. Workflow setup is optional for local ZIP builds. The two templates can run independently.

| Install command | File in `.github/workflows/` | What it does |
|-----------------|-------------------------------|--------------|
| `rtp-build --workflows:release` | `release.yml` | Creates a GitHub Release and attaches a plugin ZIP built from the pushed tag. |
| `rtp-build --workflows:wporg` | `wporg.yml` | Deploys a tagged version to an existing plugin in the WordPress.org directory via SVN. |

Run `rtp-build --workflows` to install both. Run it from the plugin root, then review and commit the generated files before tagging the release. GitHub Actions must be enabled and allowed to call the reusable workflows in `runthings-dev/.github`. [GitHub Actions repository settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository)

For WordPress.org deployment, add `WPORG_USERNAME` and `WPORG_PASSWORD` as GitHub Actions secrets. Use a WordPress.org account with SVN commit access to the plugin. The workflow uses the GitHub repository name as the plugin slug by default. If the names differ, set `plugin_slug` under the workflow job’s `with` block. [WordPress.org reusable workflow](https://github.com/runthings-dev/.github/blob/v1/.github/workflows/wporg-svn-deploy.yml)

## Releasing a version

Plain `rtp-build` builds the plugin, stages all pending changes with `git add -A`, commits them as `chore(release): deploy v{version}`, creates the tag `v{version}`, and pushes the commit and tags to the Git remote. Review your working tree before running it.

1. Commit changelog and upgrade notice changes first, for example `docs(readme): changelog for v{version}`.
2. Update the version in the plugin header, the stable tag in `readme.txt`, and any plugin version constants. Leave those changes uncommitted for the release command.
3. Run `rtp-build` from the plugin root.

### Release archives

Set `RTP_RELEASE_DIR` to archive a copy of each release ZIP at `{RTP_RELEASE_DIR}/{plugin-slug}/releases/v{version}/{plugin-slug}.zip`. You can export it in your shell startup file for repeated use. When it is unset, the command skips archiving.

### Automation

Both installed workflows run when you push a `v*` tag. Each works from its own checkout on GitHub. The GitHub Release workflow builds its own ZIP, and the WordPress.org workflow sends the deployable files to SVN. If the WordPress.org workflow is on the default branch, you can also run it manually from the Actions tab and enter the release tag in `ref`. [GitHub workflow triggers](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_dispatch)

## Reference

### Options

Run `rtp-build --help` from any directory to see usage. Run setup commands, local builds, and each of the [prompt commands](#prompts) in separate invocations.

| Option | Description |
|--------|-------------|
| `--local` | Generate the POT and ZIP locally. Skip release archiving and Git commit, tag, and push operations. |
| `--init` | Create a default `.distignore` file in the current directory |
| `--workflows` | Install both bundled GitHub Actions workflows in `.github/workflows/`. |
| `--workflows:<name>` | Install the named workflow (`release` or `wporg`). Repeat the option to select multiple workflows. |
| `-f`, `--force` | Allow replacing an existing release archive, replacing `.distignore` during init, or overwriting unmanaged or outdated workflows during workflow deployment. Also allow builds with outdated workflows. |
| `-h`, `--help` | Show command-line usage and options |

### Updating workflows

When a build reports an outdated managed workflow, update the named file and review the diff before building again. For example:

```bash
rtp-build --workflows:release --force
```

`--force` also replaces unmanaged files that share a template filename. Managed workflows with the current template version and workflows marked `-custom` are preserved. If you edit a managed workflow, add `-custom` to the version in its first line to protect your edits and skip the version check.

On a fresh setup, `rtp-build --init --workflows` creates `.distignore` before installing both workflows. To install workflows in a project that already has `.distignore`, leave out `--init` so you keep your existing exclusions. Review the resulting `.distignore` and confirm it excludes `.github/` from the plugin ZIP.

#### Runtime files in GitHub Actions

Make sure each workflow can package the runtime files your plugin needs from the tagged commit. The bundled callers leave the npm build disabled. If a plugin needs compiled npm assets, add `npm_build: true` under `with` in each caller that ships those assets, commit an up-to-date `package-lock.json` and `.distignore`, and keep the compiled runtime files out of the exclusion list. This runs `npm ci` and `npm run build` on GitHub. The shared workflows do not regenerate Composer autoloaders, so plugins that need Composer dependencies must make those files available during CI packaging. [GitHub Release workflow](https://github.com/runthings-dev/.github/blob/v1/.github/workflows/plugin-release.yml) · [WordPress.org deployment workflow](https://github.com/runthings-dev/.github/blob/v1/.github/workflows/wporg-svn-deploy.yml)

### .distignore

Use `.distignore` in the plugin root to exclude files from the ZIP. The example below shows common exclusions in rsync syntax.

```gitignore
# Ignore development files
.wordpress-org/
.git/
.github/
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

