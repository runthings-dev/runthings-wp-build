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

# Parse arguments
FORCE_OVERWRITE=false
INIT_DISTIGNORE=false
GENERATE_CHANGELOG=false
LOCAL_BUILD=false
DEPLOY_WORKFLOWS=()
while [[ $# -gt 0 ]]; do
  case $1 in
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
      echo -e "${RED}Unknown option:${NC} $1"
      echo "Usage: rtp-build [--force|-f] [--init] [--changelog] [--local] [--workflows|--workflows:<name>]"
      exit 1
      ;;
  esac
done

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
CHANGELOG_PROMPT_TEMPLATE="${SCRIPT_DIR}/../templates/changelog-prompt"
WORKFLOWS_TEMPLATE_DIR="${SCRIPT_DIR}/../templates/workflows"

# Globals
PLUGIN_DIR="$(pwd)"
PLUGINSLUG="$(basename "$PLUGIN_DIR")"
BUILD_DIR="${PLUGIN_DIR}/build"
DISTIGNORE_FILE="${PLUGIN_DIR}/.distignore"
LANG_DIR="languages"
POT_FILE="$LANG_DIR/$PLUGINSLUG.pot"
RELEASE_BASE_DIR="${RTP_RELEASE_DIR:-}"

# Handle --init: write default .distignore and exit
if [[ "$INIT_DISTIGNORE" == true ]]; then
  if [[ -f "$DISTIGNORE_FILE" ]] && [[ "$FORCE_OVERWRITE" == false ]]; then
    echo -e "${RED}Error:${NC} .distignore already exists. Use --force to overwrite."
    exit 1
  fi
  cp "$DISTIGNORE_TEMPLATE" "$DISTIGNORE_FILE"
  echo -e "${GREEN}Created${NC} .distignore at $DISTIGNORE_FILE"
  exit 0
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

  if grep -q "^\.github" "$DISTIGNORE_FILE"; then
    return 0
  fi

  # Check if .git/ exists in distignore, add .github/ after it
  if grep -q "^\.git/" "$DISTIGNORE_FILE"; then
    sed -i '' 's/^\.git\/$/&\n.github\//' "$DISTIGNORE_FILE"
    echo -e "${GREEN}Added${NC} .github/ to .distignore (after .git/)"
  else
    echo ".github/" >> "$DISTIGNORE_FILE"
    echo -e "${GREEN}Added${NC} .github/ to .distignore"
  fi
}

# Function to deploy a single workflow
deploy_workflow() {
  local workflow_name="$1"
  local template_file="${WORKFLOWS_TEMPLATE_DIR}/${workflow_name}.yml"
  local target_dir="${PLUGIN_DIR}/.github/workflows"
  local target_file="${target_dir}/${workflow_name}.yml"

  # Check template exists
  if [[ ! -f "$template_file" ]]; then
    echo -e "${RED}Error:${NC} Workflow template not found: ${workflow_name}.yml"
    return 1
  fi

  local template_version
  template_version=$(get_template_version "$workflow_name")

  # Create target directory if needed
  mkdir -p "$target_dir"

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

  cp "$template_file" "$target_file"
  echo -e "${GREEN}Deployed${NC} ${workflow_name}.yml (v${template_version})"
}

# Handle --workflows: deploy workflow templates
if [[ ${#DEPLOY_WORKFLOWS[@]} -gt 0 ]]; then
  echo "Deploying workflows..."

  # Ensure .github is in distignore
  ensure_github_in_distignore

  if [[ "${DEPLOY_WORKFLOWS[0]}" == "all" ]]; then
    # Deploy all workflows in template dir
    for template_file in "${WORKFLOWS_TEMPLATE_DIR}"/*.yml; do
      if [[ -f "$template_file" ]]; then
        workflow_name=$(basename "$template_file" .yml)
        deploy_workflow "$workflow_name"
      fi
    done
  else
    # Deploy specified workflows
    for workflow_name in "${DEPLOY_WORKFLOWS[@]}"; do
      deploy_workflow "$workflow_name"
    done
  fi

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
        WORKFLOW_OUTDATED=true
      fi
    fi
  done

  if [[ "$WORKFLOW_OUTDATED" == true ]]; then
    if [[ "$FORCE_OVERWRITE" == false ]]; then
      echo -e "${RED}Error:${NC} Outdated workflows detected. Run 'rtp-build --workflows' to update, or use --force to continue anyway."
      exit 1
    else
      echo -e "${YELLOW}Warning:${NC} Continuing with outdated workflows (--force)"
    fi
  fi
fi

# Early check: if RTP_RELEASE_DIR is set, verify we can release before building
if [[ "$LOCAL_BUILD" == false ]] && [[ -n "$RELEASE_BASE_DIR" ]]; then
  VERSION=$(grep -m1 " \* Version:" "${PLUGIN_DIR}/${PLUGINSLUG}.php" | sed 's/.*Version: *//' | tr -d '[:space:]')

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

# Copy all files to the temporary directory, excluding the patterns in .distignore
echo "Copying files to temporary directory, excluding patterns in .distignore..."
if ! rsync -av --exclude-from="${DISTIGNORE_FILE}" "${PLUGIN_DIR}/" "${TEMP_DIR}/"; then
  echo -e "${RED}Error:${NC} rsync failed."
  exit 1
fi

# Create the zip file from the temporary directory
cd "${TEMP_DIR}"
echo "Creating zip file..."
if ! zip -r "${BUILD_DIR}/${PLUGINSLUG}.zip" .; then
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
