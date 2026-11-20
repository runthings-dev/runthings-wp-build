#!/bin/bash

# Colors (only if TTY and NO_COLOR not set)
if [[ -z "$NO_COLOR" ]] && [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

print_usage() {
  cat <<'EOF'
Usage:
  rtp-build [--local] [--force]
  rtp-build --init [--workflows | --workflows:<name> ...] [--force]
  rtp-build --workflows [--force]
  rtp-build --workflows:<name> ... [--force]
  rtp-build --changelog
  rtp-build --tested-up-to <version>
  rtp-build --help

Run without options to build and release from the plugin root.

Options:
  --local                  Build the POT and ZIP locally. Skip release archiving
                           and Git commit, tag, and push operations.
  --init                   Create a default .distignore. Runs before workflows
                           when combined with --workflows or --workflows:<name>.
  --workflows              Deploy all bundled GitHub Actions workflow templates.
  --workflows:<name>       Deploy a named workflow (release or wporg).
                           Repeat this option to select multiple workflows.
  -f, --force              Allow replacing .distignore, unmanaged or outdated
                           workflows, and an existing release archive. Also
                           allow builds with outdated workflows. Workflows
                           marked -custom are preserved.
  -h, --help               Show this help.

Prompts:
  --changelog              Generate a changelog prompt from Git commits.
  --tested-up-to <version>  Fetch plugin slugs and generate a bulk Tested up to
                           prompt for the given WordPress version (e.g. 7.1).
                           Requires RTP_PLUGINS_JSON_URL.
EOF
}

# Parse arguments
FORCE_OVERWRITE=false
INIT_DISTIGNORE=false
GENERATE_CHANGELOG=false
TESTED_UP_TO_VERSION=""
LOCAL_BUILD=false
DEPLOY_WORKFLOWS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      print_usage
      exit 0
      ;;
    -f|--force)
      FORCE_OVERWRITE=true
      shift
      ;;
    --init)
      INIT_DISTIGNORE=true
      shift
      ;;
    --changelog)
      GENERATE_CHANGELOG=true
      shift
      ;;
    --tested-up-to)
      if [[ $# -lt 2 ]] || [[ ! "$2" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        echo -e "${RED}Error:${NC} --tested-up-to requires a WordPress version, e.g. --tested-up-to 7.1"
        exit 1
      fi
      TESTED_UP_TO_VERSION="$2"
      shift 2
      ;;
    --local)
      LOCAL_BUILD=true
      shift
      ;;
    --workflows)
      DEPLOY_WORKFLOWS=("all")
      shift
      ;;
    --workflows:*)
      WORKFLOW_NAME="${1#--workflows:}"
      # Validate: only alphanumeric, hyphen, underscore
      if [[ ! "$WORKFLOW_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}Error:${NC} Invalid workflow name: $WORKFLOW_NAME"
        echo "Workflow names can only contain letters, numbers, hyphens, and underscores."
        exit 1
      fi
      DEPLOY_WORKFLOWS+=("$WORKFLOW_NAME")
      shift
      ;;
    *)
      echo -e "${RED}Unknown option:${NC} $1" >&2
      print_usage >&2
      exit 1
      ;;
  esac
done

# Init and workflow deployment can run together as one setup action.
ACTIONS=()
if [[ "$INIT_DISTIGNORE" == true ]] || [[ ${#DEPLOY_WORKFLOWS[@]} -gt 0 ]]; then
  ACTIONS+=("setup (--init/--workflows)")
fi
if [[ "$GENERATE_CHANGELOG" == true ]]; then
  ACTIONS+=("--changelog")
fi
if [[ -n "$TESTED_UP_TO_VERSION" ]]; then
  ACTIONS+=("--tested-up-to")
fi
if [[ "$LOCAL_BUILD" == true ]]; then
  ACTIONS+=("--local")
fi
if [[ ${#ACTIONS[@]} -gt 1 ]]; then
  printf '%bError:%b Cannot combine these actions: %s\n' "$RED" "$NC" "${ACTIONS[*]}" >&2
  exit 1
fi

# Get the directory where this script is located (follow symlinks for npm global install)
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_SOURCE" ]]; do
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
  SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
  [[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"

# Templates
DISTIGNORE_TEMPLATE="${SCRIPT_DIR}/../templates/distignore"
CHANGELOG_PROMPT_TEMPLATE="${SCRIPT_DIR}/../templates/prompts/changelog-prompt"
TESTED_UP_TO_PROMPT_TEMPLATE="${SCRIPT_DIR}/../templates/prompts/tested-up-to-prompt"
WORKFLOWS_TEMPLATE_DIR="${SCRIPT_DIR}/../templates/workflows"

if [[ ${#DEPLOY_WORKFLOWS[@]} -gt 0 ]]; then
  if [[ "${DEPLOY_WORKFLOWS[0]}" == "all" ]]; then
    DEPLOY_WORKFLOWS=()
    for template_file in "${WORKFLOWS_TEMPLATE_DIR}"/*.yml; do
      if [[ -f "$template_file" ]]; then
        workflow_name="${template_file##*/}"
        DEPLOY_WORKFLOWS+=("${workflow_name%.yml}")
      fi
    done
    if [[ ${#DEPLOY_WORKFLOWS[@]} -eq 0 ]]; then
      printf '%bError:%b No workflow templates found in %s\n' "$RED" "$NC" "$WORKFLOWS_TEMPLATE_DIR" >&2
      exit 1
    fi
  fi

  for workflow_name in "${DEPLOY_WORKFLOWS[@]}"; do
    if [[ ! -f "${WORKFLOWS_TEMPLATE_DIR}/${workflow_name}.yml" ]]; then
      printf '%bError:%b Workflow template not found: %s.yml\n' "$RED" "$NC" "$workflow_name" >&2
      exit 1
    fi
  done
fi

# Handle --tested-up-to before any plugin or release operations
if [[ -n "$TESTED_UP_TO_VERSION" ]]; then
  PLUGINS_URL="${RTP_PLUGINS_JSON_URL:-}"
  if [[ -z "$PLUGINS_URL" ]]; then
    printf '%bError:%b Set RTP_PLUGINS_JSON_URL to the URL of your plugin slug JSON list to use --tested-up-to.\n' "$RED" "$NC" >&2
    exit 1
  fi

  for REQUIRED_TOOL in curl jq; do
    if ! command -v "$REQUIRED_TOOL" &> /dev/null; then
      echo -e "${RED}Error:${NC} --tested-up-to requires $REQUIRED_TOOL."
      exit 1
    fi
  done

  if ! PLUGINS_JSON=$(curl --fail --silent --show-error --location --connect-timeout 10 --max-time 30 -- "$PLUGINS_URL"); then
    echo -e "${RED}Error:${NC} Could not fetch plugin slugs from $PLUGINS_URL"
    exit 1
  fi

  # Validate the entire list before generating a prompt or touching the clipboard.
  if ! PLUGIN_SLUGS=$(printf '%s' "$PLUGINS_JSON" | jq -er '
    if type == "array" and length > 0 then
      if all(.[]; if type == "string" then test("^[a-z0-9]+(-[a-z0-9]+)*$") else false end) then
        .[]
      else
        error("Expected plugin slugs containing lowercase letters, numbers and hyphens")
      end
    else
      error("Expected a non-empty array of plugin slugs")
    end
  '); then
    echo -e "${RED}Error:${NC} Invalid plugin list from $PLUGINS_URL"
    exit 1
  fi

  if ! PROMPT=$(cat "$TESTED_UP_TO_PROMPT_TEMPLATE"); then
    echo -e "${RED}Error:${NC} Could not read tested-up-to prompt template."
    exit 1
  fi
  PROMPT="${PROMPT//\{\{WORDPRESS_VERSION\}\}/$TESTED_UP_TO_VERSION}"
  PROMPT="${PROMPT//\{\{SLUGS\}\}/$PLUGIN_SLUGS}"

  COPIED=false
  if command -v pbcopy &> /dev/null; then
    if printf '%s\n' "$PROMPT" | pbcopy; then
      COPIED=true
    fi
  elif command -v xclip &> /dev/null; then
    if printf '%s\n' "$PROMPT" | xclip -selection clipboard; then
      COPIED=true
    fi
  elif command -v xsel &> /dev/null; then
    if printf '%s\n' "$PROMPT" | xsel --clipboard; then
      COPIED=true
    fi
  fi

  if [[ "$COPIED" == true ]]; then
    echo -e "${GREEN}Tested-up-to prompt copied to clipboard for WordPress ${TESTED_UP_TO_VERSION}!${NC}"
    printf '\nPlugin slugs:\n%s\n' "$PLUGIN_SLUGS"
  else
    echo -e "${YELLOW}Clipboard unavailable or copy failed, printing prompt:${NC}"
    printf '\n%s\n' "$PROMPT"
  fi
  exit 0
fi

# Globals
PLUGIN_DIR="$(pwd)"
PLUGINSLUG="$(basename "$PLUGIN_DIR")"
BUILD_DIR="${PLUGIN_DIR}/build"
DISTIGNORE_FILE="${PLUGIN_DIR}/.distignore"
LANG_DIR="languages"
POT_FILE="$LANG_DIR/$PLUGINSLUG.pot"
RELEASE_BASE_DIR="${RTP_RELEASE_DIR:-}"

# Handle --init before deploying workflows, if requested.
if [[ "$INIT_DISTIGNORE" == true ]]; then
  if [[ -f "$DISTIGNORE_FILE" ]] && [[ "$FORCE_OVERWRITE" == false ]]; then
    echo -e "${RED}Error:${NC} .distignore already exists. Use --force to overwrite."
    exit 1
  fi
  if ! cp "$DISTIGNORE_TEMPLATE" "$DISTIGNORE_FILE"; then
    exit 1
  fi
  echo -e "${GREEN}Created${NC} .distignore at $DISTIGNORE_FILE"
  if [[ ${#DEPLOY_WORKFLOWS[@]} -eq 0 ]]; then
    exit 0
  fi
fi

# Handle --changelog: generate changelog prompt and copy to clipboard
if [[ "$GENERATE_CHANGELOG" == true ]]; then
  # Get commits since last tag
  LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null)
  if [[ -n "$LAST_TAG" ]]; then
    COMMITS=$(git log "${LAST_TAG}..HEAD" --oneline)
  else
    COMMITS=$(git log --oneline -20)
    echo -e "${YELLOW}Warning:${NC} No tags found, using last 20 commits"
  fi

  if [[ -z "$COMMITS" ]]; then
    echo -e "${RED}Error:${NC} No commits found since last tag (${LAST_TAG})"
    exit 1
  fi

  # Read template and inject commits
  PROMPT=$(cat "$CHANGELOG_PROMPT_TEMPLATE")
  PROMPT="${PROMPT//\{\{COMMITS\}\}/$COMMITS}"

  # Copy to clipboard
  if command -v pbcopy &> /dev/null; then
    echo "$PROMPT" | pbcopy
    COPIED=true
  elif command -v xclip &> /dev/null; then
    echo "$PROMPT" | xclip -selection clipboard
    COPIED=true
  elif command -v xsel &> /dev/null; then
    echo "$PROMPT" | xsel --clipboard
    COPIED=true
  else
    COPIED=false
  fi

  if [[ "$COPIED" == true ]]; then
    echo -e "${GREEN}Changelog prompt copied to clipboard!${NC}"
    echo ""
    echo "Commits since ${LAST_TAG:-'start'}:"
    echo "$COMMITS"
  else
    # Fallback: just print it
    echo -e "${YELLOW}No clipboard tool found (pbcopy/xclip/xsel), printing prompt:${NC}"
    echo ""
    echo "$PROMPT"
  fi
  exit 0
fi

# Function to parse workflow version from header
# Returns version string or empty if not a managed workflow
parse_workflow_version() {
  local file="$1"
  if [[ -f "$file" ]]; then
    local header
    header=$(head -1 "$file")
    if [[ "$header" =~ ^#\ runthings-wp-build:[a-zA-Z0-9_-]+\ v(.+)$ ]]; then
      echo "${BASH_REMATCH[1]}"
    fi
  fi
}

# Function to get template version
get_template_version() {
  local workflow_name="$1"
  local template_file="${WORKFLOWS_TEMPLATE_DIR}/${workflow_name}.yml"
  parse_workflow_version "$template_file"
}

# Function to check if version has -custom suffix
is_custom_version() {
  local version="$1"
  [[ "$version" == *-custom* ]]
}

# Function to ensure .github is in .distignore
ensure_github_in_distignore() {
  if [[ ! -f "$DISTIGNORE_FILE" ]]; then
    return 0
  fi

  if grep -Eq '^/?[.]github/?$' "$DISTIGNORE_FILE"; then
    return 0
  fi

  # Write through symlinks and stage the edit beside the actual file.
  local distignore_file="$DISTIGNORE_FILE"
  local link_target
  while [[ -L "$distignore_file" ]]; do
    if ! link_target=$(readlink "$distignore_file"); then
      return 1
    fi
    if [[ "$link_target" != /* ]]; then
      link_target="${distignore_file%/*}/$link_target"
    fi
    distignore_file="$link_target"
  done

  local temporary_file
  if ! temporary_file=$(mktemp "${distignore_file}.XXXXXX"); then
    return 1
  fi
  if ! cp -p "$distignore_file" "$temporary_file" || ! awk '
    { print }
    !added && /^\.git\/$/ {
      print ".github/"
      added = 1
    }
    END {
      if (!added) {
        print ".github/"
      }
    }
  ' "$distignore_file" > "$temporary_file" || ! mv -f "$temporary_file" "$distignore_file"; then
    rm -f "$temporary_file"
    return 1
  fi
  echo -e "${GREEN}Added${NC} .github/ to .distignore"
}

# Function to deploy a single workflow
deploy_workflow() {
  local workflow_name="$1"
  local template_file="${WORKFLOWS_TEMPLATE_DIR}/${workflow_name}.yml"
  local target_dir="${PLUGIN_DIR}/.github/workflows"
  local target_file="${target_dir}/${workflow_name}.yml"

  if [[ -e "$target_file" ]] && [[ ! -f "$target_file" ]]; then
    printf '%bError:%b Workflow destination is not a file: %s\n' "$RED" "$NC" "$target_file" >&2
    return 1
  fi

  local template_version
  template_version=$(get_template_version "$workflow_name")

  # Create target directory if needed
  if ! mkdir -p "$target_dir"; then
    return 1
  fi

  # Check if target already exists
  if [[ -f "$target_file" ]]; then
    local existing_version
    existing_version=$(parse_workflow_version "$target_file")

    if [[ -z "$existing_version" ]]; then
      # Not a managed workflow file
      if [[ "$FORCE_OVERWRITE" == false ]]; then
        echo -e "${YELLOW}Skipping${NC} ${workflow_name}.yml (not a managed workflow, use --force to overwrite)"
        return 0
      fi
    elif is_custom_version "$existing_version"; then
      echo -e "${YELLOW}Skipping${NC} ${workflow_name}.yml (custom version: v${existing_version})"
      return 0
    elif [[ "$existing_version" == "$template_version" ]]; then
      echo -e "${GREEN}Current${NC} ${workflow_name}.yml (v${existing_version})"
      return 0
    else
      if [[ "$FORCE_OVERWRITE" == false ]]; then
        echo -e "${YELLOW}Skipping${NC} ${workflow_name}.yml (v${existing_version} -> v${template_version}, use --force to update)"
        return 0
      fi
    fi
  fi

  # Publish the workflow only after the complete template has been copied.
  local temporary_file
  if ! temporary_file=$(mktemp "${target_dir}/.${workflow_name}.XXXXXX"); then
    return 1
  fi
  if ! cp -p "$template_file" "$temporary_file" || ! mv -f "$temporary_file" "$target_file"; then
    rm -f "$temporary_file"
    return 1
  fi
  echo -e "${GREEN}Deployed${NC} ${workflow_name}.yml (v${template_version})"
}

# Handle --workflows: deploy workflow templates
if [[ ${#DEPLOY_WORKFLOWS[@]} -gt 0 ]]; then
  echo "Deploying workflows..."

  if ! ensure_github_in_distignore; then
    printf '%bError:%b Could not update .distignore.\n' "$RED" "$NC" >&2
    exit 1
  fi

  for workflow_name in "${DEPLOY_WORKFLOWS[@]}"; do
    if ! deploy_workflow "$workflow_name"; then
      exit 1
    fi
  done

  echo -e "${GREEN}Workflow deployment complete.${NC}"
  exit 0
fi

# That's all, stop editing! Happy building.

# Function to check for required tools
check_tool() {
  if ! command -v "$1" &> /dev/null; then
    echo -e "${RED}Error:${NC} $1 is not installed."
    exit 1
  fi
}

# Extract the plugin version from the main plugin file header.
# Accepts `/*` and `/**` comments, with common variants like `* Version:`,
# ` * Version:`, or plain `Version:` inside the plugin header block.
extract_plugin_version() {
  local plugin_file="$1"

  awk '
    BEGIN {
      in_header = 0
    }
    /^<\?php/ {
      next
    }
    /^[[:space:]]*\/\*/ {
      in_header = 1
      next
    }
    in_header && /\*\// {
      in_header = 0
      next
    }
    in_header {
      line = $0
      sub(/^[[:space:]]*\*[[:space:]]*/, "", line)
      if (line ~ /^[Vv]ersion:[[:space:]]*/) {
        sub(/^[Vv]ersion:[[:space:]]*/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        print line
        exit
      }
    }
  ' "$plugin_file"
}

# Check for required tools
check_tool git
check_tool rsync
check_tool zip
check_tool mktemp
check_tool wp

if [[ "$LOCAL_BUILD" == true ]]; then
  echo -e "${YELLOW}Local build mode:${NC} skipping release archive copy and git/tag/push."
fi

# Check if the script is being run from the root directory of the plugin
if [[ ! -f "${PLUGIN_DIR}/${PLUGINSLUG}.php" ]]; then
  echo -e "${RED}Error:${NC} This script should be run from the root directory of the plugin."
  echo "Make sure you are in the ${PLUGINSLUG} directory and run the script as ./bin/build-zip.sh"
  exit 1
fi

# Check if .distignore exists
if [[ ! -f "${DISTIGNORE_FILE}" ]]; then
  echo -e "${YELLOW}Warning:${NC} .distignore file not found."
  read -p "Create one now? [Y/n] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Aborting. Run 'rtp-build --init' to create a .distignore file."
    exit 1
  fi
  cp "$DISTIGNORE_TEMPLATE" "${DISTIGNORE_FILE}"
  echo "Created .distignore - please review and commit before running the build again."
  exit 0
fi

# Check workflow versions if any managed workflows exist
WORKFLOWS_DIR="${PLUGIN_DIR}/.github/workflows"
WORKFLOW_OUTDATED=false
if [[ -d "$WORKFLOWS_DIR" ]]; then
  for workflow_file in "${WORKFLOWS_DIR}"/*.yml; do
    if [[ -f "$workflow_file" ]]; then
      workflow_name=$(basename "$workflow_file" .yml)
      existing_version=$(parse_workflow_version "$workflow_file")

      # Skip if not a managed workflow
      if [[ -z "$existing_version" ]]; then
        continue
      fi

      # Check if custom version
      if is_custom_version "$existing_version"; then
        echo -e "${YELLOW}ℹ${NC} ${workflow_name}.yml has custom version (v${existing_version}), skipping update check"
        continue
      fi

      # Get template version
      template_version=$(get_template_version "$workflow_name")

      # Skip if template doesn't exist (might be a workflow from elsewhere)
      if [[ -z "$template_version" ]]; then
        continue
      fi

      # Compare versions
      if [[ "$existing_version" != "$template_version" ]]; then
        echo -e "${RED}Outdated:${NC} ${workflow_name}.yml (v${existing_version} -> v${template_version})"
        if [[ "$FORCE_OVERWRITE" == false ]]; then
          printf '  Update with: rtp-build --workflows:%s --force\n' "$workflow_name"
        fi
        WORKFLOW_OUTDATED=true
      fi
    fi
  done

  if [[ "$WORKFLOW_OUTDATED" == true ]]; then
    if [[ "$FORCE_OVERWRITE" == false ]]; then
      echo -e "${RED}Error:${NC} Update the listed workflows, or rerun the build with --force to continue without updating them."
      exit 1
    else
      echo -e "${YELLOW}Warning:${NC} Continuing with outdated workflows (--force)"
    fi
  fi
fi

VERSION=$(extract_plugin_version "${PLUGIN_DIR}/${PLUGINSLUG}.php")

# Early check: if RTP_RELEASE_DIR is set, verify we can release before building
if [[ "$LOCAL_BUILD" == false ]] && [[ -n "$RELEASE_BASE_DIR" ]]; then
  if [[ -n "$VERSION" ]]; then
    RELEASE_DIR="${RELEASE_BASE_DIR}/${PLUGINSLUG}/releases/v${VERSION}"

    if [[ -d "$RELEASE_DIR" ]] && [[ -f "${RELEASE_DIR}/${PLUGINSLUG}.zip" ]]; then
      if [[ "$FORCE_OVERWRITE" == false ]]; then
        echo -e "${RED}Error:${NC} Release v${VERSION} already exists at ${RELEASE_DIR}/"
        echo "Please update the version number in ${PLUGINSLUG}.php before building."
        echo "Or use --force to overwrite the existing release."
        exit 1
      else
        echo -e "${YELLOW}Warning:${NC} Will overwrite existing release v${VERSION}"
      fi
    fi
  else
    echo -e "${YELLOW}Warning:${NC} Could not extract version from plugin header, will skip release copy."
  fi
fi

# Keep npm package metadata aligned with the plugin header before staging files.
if [[ -f "${PLUGIN_DIR}/package.json" ]]; then
  check_tool npm

  if [[ -z "$VERSION" ]]; then
    echo -e "${RED}Error:${NC} Could not extract plugin version to update npm package files."
    exit 1
  fi

  echo "Updating npm package files to v${VERSION}..."
  if ! npm version "$VERSION" --no-git-tag-version --ignore-scripts --allow-same-version; then
    echo -e "${RED}Error:${NC} Failed to update npm package versions."
    exit 1
  fi
fi

# Regenerate Composer autoloader if it exists
if [[ -f "${PLUGIN_DIR}/vendor/autoload.php" ]]; then
  echo "Regenerating Composer autoloader..."
  if ! composer dump-autoload; then
    echo -e "${RED}Error:${NC} Failed to regenerate Composer autoloader."
    exit 1
  fi
fi

# Generate the .pot file (with memory bump + sensible excludes)
# This kept failing with memory exhaustion so we implented this logic to parse less
echo "Generating .pot file..."
export WP_CLI_PHP_ARGS="${WP_CLI_PHP_ARGS:--d memory_limit=1024M}"

EXCLUDES="node_modules,vendor,bin,tests,.git,dist,build"

base_cmd=(wp i18n make-pot . "$POT_FILE" --domain="$PLUGINSLUG" --exclude="$EXCLUDES")

if ! "${base_cmd[@]}"; then
  echo "Retrying without JS scanning..."
  if ! "${base_cmd[@]}" --skip-js; then
    echo -e "${RED}Error:${NC} Failed to generate .pot file."
    exit 1
  fi
fi

# Create the build directory if it doesn't exist
echo "Creating build directory..."
mkdir -p "${BUILD_DIR}"

# Remove the existing zip file if it exists
if [[ -f "${BUILD_DIR}/${PLUGINSLUG}.zip" ]]; then
  echo "Removing existing zip file ${BUILD_DIR}/${PLUGINSLUG}.zip..."
  rm -f "${BUILD_DIR}/${PLUGINSLUG}.zip"
fi

# Create a temporary directory to stage the files to be zipped
TEMP_DIR="$(mktemp -d)"
echo "Created temporary directory at ${TEMP_DIR}"

# Function to clean up the temporary directory
cleanup() {
  echo "Cleaning up temporary directory..."
  rm -rf "${TEMP_DIR}"
  echo "Temporary directory cleaned up."
}

# Ensure the cleanup function is called on script exit
trap cleanup EXIT

# Stage files inside a stable plugin folder so WordPress does not derive the
# installation directory from the uploaded ZIP filename (which may have a suffix).
STAGED_PLUGIN_DIR="${TEMP_DIR}/${PLUGINSLUG}"
if ! mkdir -p "${STAGED_PLUGIN_DIR}"; then
  echo -e "${RED}Error:${NC} Failed to create staged plugin directory."
  exit 1
fi

# Keep the rsync source root unchanged so anchored .distignore patterns still apply.
echo "Copying files to temporary directory, excluding patterns in .distignore..."
if ! rsync -av --exclude-from="${DISTIGNORE_FILE}" "${PLUGIN_DIR}/" "${STAGED_PLUGIN_DIR}/"; then
  echo -e "${RED}Error:${NC} rsync failed."
  exit 1
fi

# Include the plugin folder itself as the ZIP's single top-level entry.
cd "${TEMP_DIR}" || exit 1
echo "Creating zip file..."
if ! zip -r "${BUILD_DIR}/${PLUGINSLUG}.zip" "${PLUGINSLUG}"; then
  echo -e "${RED}Error:${NC} zip failed."
  exit 1
fi
echo "Zip file created at ${BUILD_DIR}/${PLUGINSLUG}.zip"

# Clean up the temporary directory
cd "${PLUGIN_DIR}"

# Copy zip to releases archive (if RTP_RELEASE_DIR is set and version was extracted)
if [[ "$LOCAL_BUILD" == false ]] && [[ -n "$RELEASE_BASE_DIR" ]] && [[ -n "$VERSION" ]]; then
  echo "Copying zip to releases archive: ${RELEASE_DIR}/"
  mkdir -p "${RELEASE_DIR}"
  cp "${BUILD_DIR}/${PLUGINSLUG}.zip" "${RELEASE_DIR}/"
elif [[ "$LOCAL_BUILD" == false ]] && [[ -z "$RELEASE_BASE_DIR" ]]; then
  echo "Note: RTP_RELEASE_DIR not set, skipping release archive copy."
fi

# Commit, tag, and push release
if [[ "$LOCAL_BUILD" == true ]]; then
  echo "Local build mode enabled, skipping git operations."
elif [[ -n "$VERSION" ]]; then
  echo "Committing release changes..."
  git add -A
  if ! git commit -m "chore(release): deploy v${VERSION}"; then
    echo -e "${YELLOW}Warning:${NC} Nothing to commit, skipping git operations."
  else
    echo "Creating tag v${VERSION}..."
    git tag "v${VERSION}"

    echo "Pushing commit and tag to remote..."
    git push && git push --tags
  fi
else
  echo -e "${YELLOW}Warning:${NC} No version found, skipping git operations."
fi

echo "Build completed successfully."
