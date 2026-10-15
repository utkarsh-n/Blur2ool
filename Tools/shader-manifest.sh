#!/bin/zsh
# Tools/shader-manifest.sh — Xcode post-compile script of the Blur2ool app target (ARCHITECTURE.md §2 note 5, §6.6).
# OWNER: SKEL (frozen after the gate). Copies App/GPU/Shaders/*.metal and B2Shared.h byte for byte into
# <bundle>/ShaderSources/ and writes ShaderSources/ShaderManifest.json as {"files": {"<name>": "<sha256>"}}.
# The combined SHA-256 is computed in Swift by ShaderManifest.assemble (app and blur-gpucheck agree by construction).
set -e
SRC_DIR="${SRCROOT:?run from Xcode}/App/GPU/Shaders"
DEST="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/ShaderSources"
rm -rf "$DEST"
mkdir -p "$DEST"
entries=()
for f in "$SRC_DIR"/B2Shared.h "$SRC_DIR"/*.metal(N); do
  name="${f:t}"
  cp -p "$f" "$DEST/$name"
  sha="$(shasum -a 256 "$f" | cut -d' ' -f1)"
  entries+=("\"$name\": \"$sha\"")
done
print -r -- "{\"files\": {${(j:, :)entries}}}" > "$DEST/ShaderManifest.json"
print "shader-manifest: ${#entries} files → $DEST"
