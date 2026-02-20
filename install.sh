#!/bin/sh

# Unicorn: macOS Installer & Security Fixer
# This script removes the "quarantine" attribute and installs the app.

APP_NAME="unicorn.app"
INSTALL_DIR="$HOME/Library/Input Methods"
DIR="$( cd "$( dirname "$0" )" && pwd )"
APP_PATH="$DIR/$APP_NAME"

echo "--------------------------------------------------"
echo "Unicorn: macOS Installer & Security Fixer"
echo "--------------------------------------------------"

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: Could not find $APP_NAME in: $DIR"
    exit 1
fi

echo "IMPORTANT SECURITY NOTICE: PLEASE READ CAREFULLY"
echo "-----------------------------------------------"
echo "You are about to install an unverified Input Method (IM)."
echo "This carries significant security and privacy implications:"
echo ""
echo "1. FULL KEYSTROKE ACCESS (KEYLOGGING RISK):"
echo "   As an Input Method, Unicorn has the technical capability to"
echo "   monitor and record EVERY keystroke you type across ALL apps"
echo "   on your system. This includes passwords, credit card numbers,"
echo "   private messages, and other sensitive personal data."
echo ""
echo "2. LACK OF APPLE NOTARIZATION:"
echo "   This application is unsigned and has NOT been notarized by Apple."
echo "   This means Apple has not scanned this specific binary for"
echo "   malware, and its developer's identity is not verified."
echo ""
echo "3. POTENTIAL FOR CORRUPTION OR TAMPERING:"
echo "   The 'Damaged' warning you encountered is macOS's default security"
echo "   mechanism to protect you from code that may have been altered"
echo "   or injected with malicious payloads during or after download."
echo ""
echo "4. DATA EXFILTRATION RISK:"
echo "   If the app were malicious, it could potentially exfiltrate your"
echo "   typed data to a remote server without your knowledge."
echo ""
echo "BY PROCEEDING, YOU ACKNOWLEDGE THAT:"
echo "- You trust the source of this software (VicShih/unicorn-macos)."
echo "- You assume all risks associated with using unverified software."
echo "- The author provides this software 'AS IS' without any warranties."
echo "-----------------------------------------------"
echo ""

# Show SHA256 for manual verification
echo "INTEGRITY CHECK (SHA256):"
if [ -f "$APP_PATH/Contents/MacOS/unicorn" ]; then
    shasum -a 256 "$APP_PATH/Contents/MacOS/unicorn" | awk '{print "Binary Checksum: " $1}'
else
    echo "Warning: Could not locate main binary for checksum."
fi
echo ""

printf "Do you fully understand the risks and wish to install this app? [y/N]: "
read -r response

case "$response" in
    [yY][eE][sS]|[yY]) 
        echo ""
        echo "Step 1: Removing the 'damaged' flag (quarantine)..."
        xattr -rd com.apple.quarantine "$APP_PATH"
        
        echo "Step 2: Installing to $INSTALL_DIR..."
        mkdir -p "$INSTALL_DIR"
        rm -rf "$INSTALL_DIR/$APP_NAME"
        cp -R "$APP_PATH" "$INSTALL_DIR/"
        
        echo "Step 3: Registering with macOS..."
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_DIR/$APP_NAME"
        
        echo "Step 4: Restarting Unicorn..."
        pkill -f "$APP_NAME" || true
        
        echo ""
        echo "Success! Unicorn has been installed."
        echo "IMPORTANT: You may still need to authorize it manually:"
        echo "1. Go to System Settings > Keyboard > Input Sources > Edit."
        echo "2. Add 'Unicorn' from the list."
        echo "3. If prompted about an unverified developer, right-click"
        echo "   $INSTALL_DIR/$APP_NAME and select 'Open'."
        ;;
    *)
        echo "Installation cancelled. No changes were made."
        exit 0
        ;;
esac
echo "--------------------------------------------------"
