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
    *)
      echo -e "${RED}Unknown option:${NC} $1"
      echo "Usage: rtp-build [--force|-f] [--init] [--changelog]"
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

  # Copy to clipboard (macOS)
  if command -v pbcopy &> /dev/null; then
    echo "$PROMPT" | pbcopy
    echo -e "${GREEN}Changelog prompt copied to clipboard!${NC}"
    echo ""
    echo "Commits since ${LAST_TAG:-'start'}:"
    echo "$COMMITS"
  else
    # Fallback: just print it
    echo "$PROMPT"
  fi
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
check_tool rsync
check_tool zip
check_tool mktemp
check_tool wp

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

# Early check: if RTP_RELEASE_DIR is set, verify we can release before building
if [[ -n "$RELEASE_BASE_DIR" ]]; then
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
if [[ -n "$RELEASE_BASE_DIR" ]] && [[ -n "$VERSION" ]]; then
  echo "Copying zip to releases archive: ${RELEASE_DIR}/"
  mkdir -p "${RELEASE_DIR}"
  cp "${BUILD_DIR}/${PLUGINSLUG}.zip" "${RELEASE_DIR}/"
elif [[ -z "$RELEASE_BASE_DIR" ]]; then
  echo "Note: RTP_RELEASE_DIR not set, skipping release archive copy."
fi

# Commit, tag, and push release
if [[ -n "$VERSION" ]]; then
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
