#!/bin/bash
TARGET="AllBuilds"
mkdir -p "$TARGET"



# 2. Copy the Android APK
if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    cp build/app/outputs/flutter-apk/app-release.apk "$TARGET/M3Player-Android.apk"
    echo "✅ Copied Android APK into AllBuilds/"
fi

# 3. Copy the Linux Native Bundle
if [ -d "build/linux/x64/release/bundle" ]; then
    rm -rf "$TARGET/Linux-Native"
    cp -r "build/linux/x64/release/bundle" "$TARGET/Linux-Native"
    
    echo "📦 Creating .tar.gz for Linux native bundle..."
    tar -czf "$TARGET/M3Player-Linux-Native.tar.gz" -C build/linux/x64/release/bundle .
    
    echo "📦 Building Flatpak..."
    rm -rf build-dir repo
    flatpak-builder --repo=repo build-dir com.example.M3Player.json
    flatpak build-bundle repo "$TARGET/M3Player-Linux.flatpak" com.example.M3Player
    
    echo "✅ Copied Linux Native bundle into AllBuilds/Linux-Native, created .tar.gz, and built Flatpak"
fi

# 4. Copy the Web Build
if [ -d "build/web" ]; then
    mkdir -p "$TARGET/Web-App"
    rm -rf "$TARGET/Web-App"/*
    cp -r build/web/* "$TARGET/Web-App/"
    echo "✅ Copied Web build into AllBuilds/Web-App"
fi

echo ""
echo "🎉 All builds have been successfully gathered in the '$TARGET' folder!"
