#!/bin/bash

# Author: La Barge, Alexander
# Date: 19 Apr 24

set -e

# Use Android Flash Tool for the below stable build, or let script execute which will do the same, but faster
# Stable with:
# Link: https://dl.google.com/dl/android/aosp/shiba-ap1a.240405.002.b1-factory-4eaef674.zip

BASE_DIR="${HOME}/pixel8-kernel-build-v5"
DIST_DIR="${BASE_DIR}/kernel_build_finished"
BACKUP_REPO="${BASE_DIR}/backup_repo"
FACTORY_IMAGE_DIR="${BASE_DIR}/shiba_stable_android14-5.15"
ZIP_FILE="shiba-ap1a.240405.002.b1-factory-4eaef674.zip"
SUB_DIR_IN_ZIP="shiba-ap1a.240405.002.b1"
DOWNLOAD_URL="https://dl.google.com/dl/android/aosp/${ZIP_FILE}"
IMAGE_ZIP_PATH="${FACTORY_IMAGE_DIR}/${SUB_DIR_IN_ZIP}/image-${SUB_DIR_IN_ZIP}.zip"
FLASH_ALL_SCRIPT="${FACTORY_IMAGE_DIR}/${SUB_DIR_IN_ZIP}/flash-all.sh"

# Create necessary directories
mkdir -p "${FACTORY_IMAGE_DIR}"
mkdir -p "${DIST_DIR}"
mkdir -p "${BACKUP_REPO}"

function extract_and_move_vbmeta() {
    local image_zip="$1"
    local dist_dir="$2"
    local vbmeta_img="vbmeta.img"

    echo "Extracting vbmeta.img from $image_zip..."
    unzip -q "$image_zip" "$vbmeta_img" -d "/tmp"

    # Check if vbmeta.img was extracted
    if [[ -f "/tmp/$vbmeta_img" ]]; then
        echo "Moving vbmeta.img to $dist_dir..."
        mv "/tmp/$vbmeta_img" "$dist_dir"
        echo "vbmeta.img has been successfully moved."
    else
        echo "Failed to extract vbmeta.img. It may not exist in the zip file."
        return 1 # Return failure
    fi
}

# Step 1: Bring Device Back to Stable User Release by downloading and flashing the stable build
echo "Downloading and unzipping the stable factory image..."
wget "${DOWNLOAD_URL}" -O "${FACTORY_IMAGE_DIR}/${ZIP_FILE}"
unzip -q "${FACTORY_IMAGE_DIR}/${ZIP_FILE}" -d "${FACTORY_IMAGE_DIR}"
extract_and_move_vbmeta "$IMAGE_ZIP_PATH" "$DIST_DIR"

# Verify if the image zip exists and flash-all script is present.
if [ -f "${IMAGE_ZIP_PATH}" ] && [ -f "${FLASH_ALL_SCRIPT}" ]; then
    echo "Stable image and flash script found, starting the flash process..."
    cd "${FACTORY_IMAGE_DIR}/${SUB_DIR_IN_ZIP}"
    adb reboot bootloader
    sleep 5
    bash ./flash-all.sh
else
    echo "Error: Required files for flashing are missing."
    exit 1
fi

# Step 2: Get Kernel Repo
echo "Syncing Stable Android Kernel Repo"

# Initialize the repository
repo init -u https://android.googlesource.com/kernel/manifest

# Get android14-5.15-2024-04 Stable XML using the raw file URL
wget -O manifest_11657131.xml https://raw.githubusercontent.com/alexander-labarge/android_dev/main/manifest_11657131.xml

# Copy the specific manifest file to the .repo directory
cp manifest_11657131.xml ./.repo/manifests/

# Init the stable Pixel 8 Android Kernel Repo
repo init -m manifest_11657131.xml

# Sync the repository
repo sync -j$(nproc)

# Step 3: Get Kernel Repo
echo "Backing up the Repo to: ${BACKUP_REPO}"
echo "If you need a fresh sync again, you can just rsync against the above directory."

# Make the backup (every build needs a new repo apparently)
rsync -avh --progress ${BASE_DIR} "${BACKUP_REPO}"

# Make your changes here
echo "Apply custom changes to the kernel source code..."
sleep 2
# Menu Config
tools/bazel run //common:kernel_aarch64_config -- menuconfig

# Build kernel distribution
echo "Building custom android14-5.15-2024-04 based on your preferences."
sleep 2
tools/bazel run //common:kernel_aarch64_dist -- --dist_dir="${DIST_DIR}"

# Test the built kernel Image
if [[ -f "${DIST_DIR}/Image" ]]; then
    strings "${DIST_DIR}/Image" | grep 'Linux version' || { 
      echo "Kernel Image verification failed: Linux version string missing."; 
      exit 1; 
    }
else
    echo "Kernel Image does not exist in the distribution directory."
    exit 1
fi
# Build the kernel distribution
tools/bazel run //common:kernel_aarch64_dist -- --dist_dir="${DIST_DIR}"

# Check if both boot.img and vbmeta.img exist in the defined distribution directory.
if [ -f "${DIST_DIR}/boot.img" ] && [ -f "${DIST_DIR}/vbmeta.img" ]; then
    echo "Both boot.img and vbmeta.img files are present. Proceeding with the next steps."
else
    echo "Error: The required files are missing in ${DIST_DIR}."
    if [ ! -f "${DIST_DIR}/boot.img" ]; then
        echo "- boot.img is missing."
    fi
    if [ ! -f "${DIST_DIR}/vbmeta.img" ]; then
        echo "- vbmeta.img is missing."
    fi
    exit 1
fi

# Instructing the user to enable USB debugging and Developer options.
echo "Before proceeding, please ensure the following steps are completed on your device:"

# Provide clear instructions for the user to follow.
cat <<EOF
1. Enable Developer Options:
   - Go to Settings > About phone.
   - Tap Build number seven times until you see the message "You are now a developer!"

2. Enable USB debugging:
   - Go back to Settings > System > Advanced > Developer options.
   - Find and enable 'USB debugging'.

3. Set USB Preferences to File Transfer:
   - Connect your device to your computer via USB.
   - If prompted, select 'File Transfer' mode as the USB preference.

4. Toggle OEM Unlocked -> Enabled

EOF

# Wait for the user to confirm they have completed the steps.
read -p "Press Enter once you have completed the above steps and are ready to continue..."

# Checking if adb devices command can find any devices
if adb devices | grep -q 'device$'; then
    echo "ADB has detected your device. Rebooting into bootloader mode."
    adb reboot bootloader
    echo "Delaying 10 seconds to give bootloader chance to come up."
    sleep 10
else
    echo "ADB failed to detect your device. Please ensure USB Debugging is enabled and connected properly."
    exit 1
fi

# Function to check OS functionality interactively
function verify_os_functionality {
  local user_input=""
  while true; do
    read -p "Has the OS booted successfully and is functioning as expected? (yes/no): " user_input
    case $user_input in
        [Yy][Ee][Ss] ) echo "User confirmed the OS is functioning correctly."; return 0;;
        [Nn][Oo] ) echo "User indicated the OS is not functioning correctly. Exiting..."; return 1;;
        * ) echo "Please answer yes or no.";;
    esac
  done
}

# Function to flash the device with a new kernel image
function flash_custom_kernel {
  echo "Beginning flash process..."  
  adb reboot bootloader
  echo "Device rebooting into bootloader mode..."

  fastboot oem disable-verification
  fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
  fastboot -w 
  fastboot flash boot boot.img
  fastboot reboot  
  echo "Device Flashed - should reboot on its own"
}

# Ensure that boot.img exists and is in the right place before running this command.
if [[ -f boot.img ]]; then
    fastboot boot boot.img
    echo "Booting from boot.img..."
else
    echo "boot.img does not exist in the distribution directory."
    exit 1
fi

# Wait 20 seconds for the connected device to boot after executing the fastboot command.
sleep 20

# Check if the device comes online after the kernel boots up.
if adb devices | grep -q 'device$'; then
    echo "Device successfully booted. Gathering kernel version information..."
    
    # Retrieve kernel version using adb shell cat command and display it to the user.
    kernel_version=$(adb shell cat /proc/version)
    echo "Kernel Version: $kernel_version"
    
    # Ask the user to confirm if the OS is running fine.
    if verify_os_functionality; then
        # If the OS is running fine - let's get this done
        flash_custom_kernel
    else
        echo "OS verification failed by user input. Exiting..."
        exit 1
    fi
else
    echo "Failed to detect device after boot. Please check the device status and try again."
    exit 1
fi
