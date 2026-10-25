import QtQuick
import Quickshell.Services.UPower
import qs.components
import qs.services
import qs.utils

MaterialIcon {
    required property color colour

    animate: true
    text: {
        if (!UPower.displayDevice.isLaptopBattery) {
            if (PowerProfiles.profile === PowerProfile.PowerSaver)
                return "energy_savings_leaf";
            if (PowerProfiles.profile === PowerProfile.Performance)
                return "rocket_launch";
            return "balance";
        }
        if ([UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(UPower.displayDevice.state))
            return "battery_android_bolt";
        const p = UPower.displayDevice.percentage;
        return p >= 0.95 ? "battery_android_full" : `battery_android_${Math.floor(p * 7)}`;
    }
    color: !UPower.onBattery || UPower.displayDevice.percentage > 0.2 ? colour : Colours.palette.m3error
    fill: 1
}
