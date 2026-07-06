#!/bin/bash
set -e

echo "====================================="
echo "  Building Tilawah AI for Production"
echo "====================================="

# You must set API_BASE_URL to your production backend URL
if [ -z "$API_BASE_URL" ]; then
  echo "Error: API_BASE_URL is not set."
  echo "Example: export API_BASE_URL=https://api.tilawah.ai"
  exit 1
fi

echo "Using API_BASE_URL: $API_BASE_URL"

# Clean previous builds
flutter clean
flutter pub get

# Build Android AppBundle
echo "Building Android AppBundle..."
flutter build appbundle --release --dart-define=API_BASE_URL=$API_BASE_URL

# Build iOS IPA (Requires macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
  echo "Building iOS IPA..."
  flutter build ipa --release --dart-define=API_BASE_URL=$API_BASE_URL
else
  echo "Skipping iOS build (not on macOS)."
fi

# Build Web (Optional)
# echo "Building Web..."
# flutter build web --release --dart-define=API_BASE_URL=$API_BASE_URL

echo "Build complete!"
