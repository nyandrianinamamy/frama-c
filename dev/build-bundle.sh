#!/usr/bin/env bash
##########################################################################
#                                                                        #
#  SPDX-License-Identifier LGPL-2.1                                      #
#  Copyright (C)                                                         #
#  CEA (Commissariat à l'énergie atomique et aux énergies alternatives)  #
#                                                                        #
##########################################################################

set -euo pipefail

# Path to the current script directory
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
# Path to Frama-C's root
ROOT=$(realpath "$SCRIPT_DIR/..")

function echo_red {
  echo -e "\e[31m$1\e[0m"
}
function echo_green {
  echo -e "\e[32m$1\e[0m"
}

function show_step {
  echo ""
  echo -e "\e[34m### $1\e[0m"
}

# CI variable set by Gitlab
CI=${CI:-false}

# Customizing variables specific to the bundle
BUNDLE_GUI=${BUNDLE_GUI:-true}
BUNDLE_EXTERNAL_PLUGINS=${BUNDLE_EXTERNAL_PLUGINS:-}
BUNDLE_IVETTE_PLUGINS=${BUNDLE_IVETTE_PLUGINS:-}
BUNDLE_CUSTOM_OUI_FILE=${BUNDLE_CUSTOM_OUI_FILE:-}
BUNDLE_ARCH=${BUNDLE_ARCH:-linux-x86-64}
BUNDLE_EXT=${BUNDLE_EXT:-run}

# Customizing variables used in other CI jobs
LAST_OCAML=$(opam switch list-available --all \
  | grep ocaml-base-compiler \
  | awk '{ print $2 }' \
  | sort --version-sort \
  | tail -1)
OCAML=${OCAML:-$LAST_OCAML}
DEFAULT=${DEFAULT:-master}

while [ $# -gt 0 ]
do
  case "$1" in
    -h|-help|--help)
      echo "Build Frama-C binary bundle"
      echo ""
      echo "USAGE"
      echo ""
      echo "  ${BASH_SOURCE[0]} [OPTIONS]"
      echo ""
      echo "OPTIONS"
      echo "  --help"
      echo "  --no-gui                      Do not build and package the GUI."
      echo "  --external-plugins <plugins>  Bundle the given external plugins."
      echo "                                Comma-separated list of <name>:<group>/<project>."
      echo "                                The <name> is used as folder name when"
      echo "                                cloning the repository, the <group>/<project>"
      echo "                                part is a project on git.frama-c.com."
      echo "                                (default to '')."
      echo "  --ivette-plugins <plugins>    Bundle the given Ivette plugins."
      echo "                                Comma-separated list of <name>:<group>/<project>."
      echo "                                The <name> is used as folder name when"
      echo "                                cloning the repository, the <group>/<project>"
      echo "                                part is a project on git.frama-c.com."
      echo "                                (default to '')."
      echo "  --custom-oui-file <file>      Use provided Oui file."
      echo "  --bundle-arch <arch>          Architecture used in the bundle filename"
      echo "                                (default to 'linux-x86-64')"
      echo "  --bundle-ext <ext>            Extension of the bundle filename"
      echo "                                (default to 'run')"
      echo ""
      echo "ENVIRONMENT VARIABLES"
      echo ""
      echo "  BUNDLE_GUI=true|false              (overridden by --no-gui)"
      echo "  BUNDLE_EXTERNAL_PLUGINS=<plugins>  (also set by --external-plugins \"<plugins>\")"
      echo "  BUNDLE_IVETTE_PLUGINS=<plugins>    (also set by --ivette-plugins \"<plugins>\")"
      echo "  BUNDLE_CUSTOM_OUI_FILE=<file>      (also set by --custom-oui-file \"<file>\")"
      echo "  BUNDLE_ARCH=<arch>                 (also set by --bundle-arch)"
      echo "  BUNDLE_EXT=<ext>                   (also set by --bundle-ext)"
      echo "  CI=true|false                      (default to false)"
      echo "  OCAML=<version>                    OCaml version to use for the switch (default to 5.5)"
      echo "  DEFAULT=<branch>                   Branch to checkout for external plugins"
      echo "                                     (default to the same branch as Frama-C, or master)"
      exit 0
      ;;
    --no-gui)
      BUNDLE_GUI=false
      ;;
    --external-plugins)
      shift
      BUNDLE_EXTERNAL_PLUGINS="$1"
      ;;
    --ivette-plugins)
      shift
      BUNDLE_IVETTE_PLUGINS="$1"
      ;;
    --custom-oui-file)
      shift
      BUNDLE_CUSTOM_OUI_FILE="$1"
      ;;
    --bundle-arch)
      shift
      BUNDLE_ARCH="$1"
      ;;
    --bundle-ext)
      shift
      BUNDLE_EXT="$1"
      ;;
    *)
      echo_red "Unknown option '$1'"
      exit 1
      ;;
  esac
  shift
done

OUI_FILE="$SCRIPT_DIR/oui.json"
if [ "$BUNDLE_CUSTOM_OUI_FILE" != "" ]; then
  OUI_FILE="$BUNDLE_CUSTOM_OUI_FILE"
elif [ "$BUNDLE_GUI" != "true" ]; then
  OUI_FILE="$SCRIPT_DIR/oui-no-gui.json"
fi

# Fully qualified paths to _opam and bundle
# (Some part of the script still use relative paths, be careful when
# changing those variables)
OPAM="$ROOT/_opam"
export OPAM
BUNDLE="$ROOT/bundle"
export BUNDLE

# Debug infos
if [ "$CI" = "true" ]; then
  show_step "Debug information"
  echo_green "  CI=${CI}"
  echo_green "  BUNDLE_GUI=${BUNDLE_GUI}"
  echo_green "  BUNDLE_EXTERNAL_PLUGINS=${BUNDLE_EXTERNAL_PLUGINS}"
  echo_green "  BUNDLE_IVETTE_PLUGINS=${BUNDLE_IVETTE_PLUGINS}"
  echo_green "  BUNDLE_CUSTOM_OUI_FILE=${BUNDLE_CUSTOM_OUI_FILE}"
  echo_green "  BUNDLE_ARCH=${BUNDLE_ARCH}"
  echo_green "  BUNDLE_EXT=${BUNDLE_EXT}"
  echo_green "  OUI_FILE=${OUI_FILE}"
  echo_green "  LAST_OCAML=${LAST_OCAML}"
  echo_green "  OCAML=${OCAML}"
  echo_green "  DEFAULT=${DEFAULT}"
  echo_green "  OPAM=${OPAM}"
  echo_green "  BUNDLE=${BUNDLE}"
fi

# Reset bundle

rm -rf "$BUNDLE"
mkdir  "$BUNDLE"

# Pull external and ivette plugins
## Parse variables
declare -A plugins=()
IFS="," read -r -a tmpplugins <<< "$BUNDLE_EXTERNAL_PLUGINS"
for tmpplugin in "${tmpplugins[@]}"; do
  IFS=":" read -r name repo <<< "$tmpplugin"
  plugins[$name]=$repo
done
declare -A ivette_plugins=()
IFS="," read -r -a tmpplugins <<< "$BUNDLE_IVETTE_PLUGINS"
for tmpplugin in "${tmpplugins[@]}"; do
  IFS=":" read -r name repo <<< "$tmpplugin"
  ivette_plugins[$name]=$repo
done

## Pull external and ivette plugins

# prints
# - "$2" if it is a branch name in remote $1,
# - else "$DEFAULT" if it is set and $DEFAULT is a branch name in remote $1,
# - else master
get_matching_branch () {
  if   git ls-remote --quiet --exit-code "$1" "$2" >/dev/null 2>/dev/null;
  then echo "$2"
  elif git ls-remote --quiet --exit-code "$1" "$DEFAULT" >/dev/null 2>/dev/null;
  then echo "$DEFAULT"
  else echo master
  fi
}

if [ -n "$(git rev-parse --is-inside-work-tree 2>/dev/null)" ]; then
  git_current_branch="$(git branch --show-current)"
  : "${git_current_branch:=${CI_COMMIT_REF_NAME:-$DEFAULT}}"
else
  git_current_branch=${CI_COMMIT_REF_NAME:-$DEFAULT}
fi

if [ "${#plugins[@]}" -gt 0 ]; then
  show_step "Pull external plugins"
  echo_green "  Currently on branch $git_current_branch"

  for name in "${!plugins[@]}"; do
    echo_green "  Cloning $name"
    location="${plugins[$name]}"
    if [ "$CI" = "true" ]; then
      repo="https://git-token:$FRAMA_CI_BOT_API_TOKEN@git.frama-c.com/$location.git"
    else
      repo="git@git.frama-c.com:$location.git"
    fi
    branch="$(get_matching_branch "$repo" "$git_current_branch")"
    git clone --depth=1 --branch="$branch" "$repo" "$ROOT/plugins/$name"
  done
fi
if [ "${#ivette_plugins[@]}" -gt 0 ]; then
  show_step "Pull Ivette plugins"
  echo_green "  Currently on branch $git_current_branch"

  for name in "${!ivette_plugins[@]}"; do
    echo_green "  Cloning $name"
    location="${ivette_plugins[$name]}"
    if [ "$CI" = "true" ]; then
      repo="https://git-token:$FRAMA_CI_BOT_API_TOKEN@git.frama-c.com/$location.git"
    else
      repo="git@git.frama-c.com:$location.git"
    fi
    branch="$(get_matching_branch "$repo" "$git_current_branch")"
    git clone --depth=1 --branch="$branch" "$repo" "$ROOT/ivette/src/frama-c/plugins/$name"
  done
fi

# _opam
show_step "Build local opam switch"

rm -rf "$OPAM"
opam switch create --empty .
opam switch set-invariant "ocaml>=$OCAML" --no-action
eval "$(opam env)"

opam pin add -n \
  https://github.com/Frama-C/ocaml-universal-installer.git#reference

opam install -y --confirm-level=unsafe-yes \
  oui

show_step "Install Frama-C dependencies"
"$ROOT/dev/bundle-install-dependencies.sh"

# Install plugins dependencies
for plugin in "$ROOT"/plugins/*; do
  installdeps="${plugin}/dev/bundle-install-dependencies.sh"
  if [ -f "${installdeps}" ]; then
    show_step "Install ${plugin} dependencies"
    bash "${installdeps}"
  fi
done

# build Frama-C
show_step "Build Frama-C"

dune clean
dune build --release --promote-install-files=false @install
dune install --root . --prefix "./bundle" --relocatable

# copy dependencies
show_step "Copy Frama-C's runtime dependencies to the bundle"
./dev/bundle-copy-runtime-dependencies.sh

for plugin in "$ROOT"/plugins/*; do
  copydeps="${plugin}/dev/bundle-copy-runtime-dependencies.sh"
  if [ -f "${copydeps}" ]; then
    show_step "Copy ${plugin}'s runtime dependencies to the bundle"
    bash "${copydeps}"
  fi
done

# Bundle GUI
if [ "$BUNDLE_GUI" = "true" ]; then
  # build Ivette
  show_step "Build Ivette"

  pushd "$ROOT/ivette" || exit 1;

  make clean

  echo_green "  generate API"
  "$BUNDLE/bin/frama-c" -load-plugin api_generator -server-tsc src

  echo_green "  configure packages"
  find src -name "pkg.json" -print0 \
    | xargs -0 node ./configure.js src/renderer/loader.ts

  echo_green "  configure sandboxes"
  find src/sandbox -name "*.tsx" -print0 \
    | xargs -0 node ./sandboxer.js src/renderer/sandbox.ts

  echo_green "  build package"
  yarn install
  yarn run build
  yarn run electron-builder build --dir

  cp -r ./dist/linux-*unpacked "$BUNDLE/lib/frama-c/gui"

  popd
fi

# Finalize bundle
show_step "Clean build artifacts from the directory"
"$ROOT"/dev/clean-bundle.sh --quiet bundle

show_step "Create Oui bundle"
oui build "$OUI_FILE" -o "frama-c-$BUNDLE_ARCH.$BUNDLE_EXT" bundle

if [ -f "frama-c-$BUNDLE_ARCH.pkg" ]; then # sign macOS bundle
  show_step "Sign MacOS bundle"
  xattr -dr com.apple.quarantine "frama-c-$BUNDLE_ARCH.pkg"
  codesign -s - --deep --force ./"frama-c-$BUNDLE_ARCH.pkg"
fi
