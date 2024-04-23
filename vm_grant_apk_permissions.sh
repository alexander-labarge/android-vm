#!/bin/bash

APP_PACKAGE="com.labarge.ig88vm"

declare -a PERMISSIONS=(
    "android.permission.MANAGE_VIRTUAL_MACHINE"
    "android.permission.INTERNET"
    "android.permission.ACCESS_NETWORK_STATE"
    "android.permission.ACCESS_WIFI_STATE"
)

grant_permissions() {
    for perm in "${PERMISSIONS[@]}"
    do
        adb shell su -c "pm grant $APP_PACKAGE $perm"
        echo "Granted $perm to $APP_PACKAGE"
    done
}

if adb devices | grep -q 'device$'; then
    echo "Device is connected, proceeding to grant permissions..."
    grant_permissions
else
    echo "No devices connected. Please connect a device and try again."
fi