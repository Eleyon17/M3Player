#!/bin/bash

# Define the target directory
TARGET_DIR="CompileFilesWindows"

# Create the directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Mirror the required directories using rsync (deletes files in the target that no longer exist in the source)
rsync -av --delete lib/ "$TARGET_DIR/lib/"
rsync -av --delete windows/ "$TARGET_DIR/windows/"

# Copy individual configuration files
cp pubspec.yaml pubspec.lock .metadata analysis_options.yaml "$TARGET_DIR/"

echo ""
echo "✅ Successfully mirrored the Windows compile files into the '$TARGET_DIR' directory!"
