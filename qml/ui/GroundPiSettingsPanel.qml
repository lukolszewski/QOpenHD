import QtQuick 2.12
import QtQuick.Controls 2.12
import QtQuick.Layouts 1.12

import Qt.labs.settings 1.0

import OpenHD 1.0

GroundPiSettingsPanelForm {
    property double lastSettingsLoad: 0
    property var pendingPreset: ({})
    property bool requireReboot: false

/* for later use when saving settings

    save.onClicked: {
        requireReboot = false;

        if (isPreset) {
            configurePreset();
            requireReboot = true;
        }

        savedTimer.stop()
        showSavedCheckmark = false
        writeRemoteSettings();
    }


    Timer {
        id: savedTimer
        running: false
        interval: 5000
        repeat: false
        onTriggered: {
            showSavedCheckmark = false
        }
    }
*/

    Timer {
        interval: 1000;
        running: true;
        repeat: true
        onTriggered: {
            
/*TODO for testing this is commented out             
            if (!openHDSettings.ground_available) {
                return;
            }
*/
            /*
             * Don't fetch settings if the drone is armed, this is an early implementation of
             * a "radio silence" feature to avoid doing any unnecessary automatic tasks that
             * could cause interference or affect the video reception in any way.
             *
             * The microservice code will have a more general radio silence switch to eliminate
             * unnecessary air traffic, but this settings timer is a big one due to how much CPU
             * time the settings processing code uses right now, and it's all in the main thread.
             */
            if (OpenHD.armed) {
                return;
            }

            /*
             * Don't fetch settings if the settings panel is already open, this avoids changing
             * settings UI controls while the user is trying to set them.
             */
            if (settings_popup.visible) {
                return;
            }

            var currentTime = (new Date).getTime();
            if (currentTime - lastSettingsLoad > 60000) {
                lastSettingsLoad = currentTime;
                console.log("Auto-fetching ground station settings");
                openHDSettings.fetchSettings();
            }
        }
    }

    SettingsMap {
        id: settingsMap
    }

    /*
     * These are models for the settings visible in each tab. They are dynamically generated at runtime
     * to allow different settings to be visible as needed, and to allow for dynamic row types.
     *
     */
    ListModel {
        dynamicRoles: true
        id: generalSettingsModel
    }

    ListModel {
        dynamicRoles: true
        id: radioSettingsModel
    }

    ListModel {
        dynamicRoles: true
        id: cameraSettingsModel
    }

    ListModel {
        dynamicRoles: true
        id: ethernetSettingsModel
    }

    ListModel {
        dynamicRoles: true
        id: otherSettingsModel
    }

/* for later use when saving settings

    Connections {
        target: openHDSettings

        function onSavingSettingsStart() {
            localMessage("Saving ground settings", 6);
        }

        function onSavingSettingsFinished() {
            localMessage("Ground settings saved", 6);
            showSavedCheckmark = true
            savedTimer.start()
            if (requireReboot) {
                // display reboot message and send message to ground to trigger single smartsync at next boot
            }
        }

        function onSavingSettingsFailed() {
            localMessage("%1 ground settings did not save!".arg(failCount), 4);
            // todo: show failure message instead
            showSavedCheckmark = true
        }
    }
*/

    function configurePreset() {
        for (var setting in pendingPreset) {
            var value = pendingPreset[setting];

            var model = undefined;

            if (settingsMap.generalSettingsMap[setting] !== undefined) {
                model = generalSettingsModel;
            } else if (settingsMap.radioSettingsMap[setting] !== undefined) {
                model = radioSettingsModel;
            } else if (settingsMap.cameraSettingsMap[setting] !== undefined) {
                model = cameraSettingsModel;
            } else if (settingsMap.ethernetSettingsMap[setting] !== undefined) {
                model = ethernetSettingsModel;
            } else {
                model = otherSettingsModel;
            }

            if (model !== undefined) {
                for(var index = 0; index < model.count; index++) {
                    var item = model.get(index);
                    var modelSetting = item['setting'];
                    if (modelSetting != setting) {
                        continue;
                    }

                    model.get(index).value = value;
                }
            }
        }
    }

    /*
     * Remote OpenHD settings on the ground station
     *
     */
    Connections {
        target: openHDSettings

        function onAllSettingsChanged() {
            /*
             * Clear the local ListModels for each tab, the ListView in each tab uses these to decide
             * what to draw.
             *
             */
            generalSettingsModel.clear();
            radioSettingsModel.clear();
            cameraSettingsModel.clear();
            ethernetSettingsModel.clear();
            otherSettingsModel.clear();

            /*
             * Helper to retrieve and map settings values to a normal representation for display.
             *
             *
             * When the remote settings are saved again, we map these values back to the representation
             * expected by the ground station. This should avoid introducing subtle bugs on the ground station
             * side of things.
             *
             */
            function _process(setting, initialValue, model, mapping, disabled) {
                var order = mapping[setting]["order"];
                if (order === undefined) {
                    order = "";
                }
                var itemTitle = mapping[setting]["title"];
                var itemInfo = mapping[setting]["info"];
                if (itemInfo === undefined) {
                    itemInfo = "N/A";
                }
                var itemType  = mapping[setting]["itemType"];
                var rangeType = mapping[setting]["rangeType"];

                /* not all of these are used for each setting, they don't need to be defined in the
                   mapping if they aren't needed as the QML component will simply not attempt to use them
                */
                var trueValue    = mapping[setting]["trueValue"];
                var falseValue   = mapping[setting]["falseValue"];
                var choiceValues = mapping[setting]["choiceValues"];
                var lowerLimit   = mapping[setting]["lowerLimit"];
                var upperLimit   = mapping[setting]["upperLimit"];
                var interval     = mapping[setting]["interval"];
                var unit         = mapping[setting]["unit"];
                var from         = mapping[setting]["from"];
                var to           = mapping[setting]["to"];
                var checkedValue = mapping[setting]["checkedValue"];
                var uncheckedValue = mapping[setting]["uncheckedValue"];
                var checked = (initialValue == checkedValue) ? true : false;

                var finalValue;

                /* these all need to be mapped because the values coming from the C++ side
                   are of type 'QVariant', not actual types that can be worked with
                */
                if (itemType === "bool") {
                    finalValue = (initialValue == trueValue) ? true : false;
                } else if (itemType === "choice") {
                    finalValue = String(initialValue);
                } else if (itemType === "switch") {
                    finalValue = Number(initialValue);
                } else if (itemType === "range") {
                    finalValue = Number(initialValue);
                } else if (itemType === "number") {
                    finalValue = Number(initialValue);
                } else if (itemType === "string") {
                    finalValue = String(initialValue);
                } else {
                    finalValue = initialValue;
                }

                configureWithSetting(setting, finalValue);

                model.append({"order": order,
                              "title": itemTitle,
                              "setting": setting,
                              "choiceValues": choiceValues,
                              "lowerLimit": lowerLimit,
                              "upperLimit": upperLimit,
                              "interval": interval,
                              "itemType": itemType,
                              "originalValue": finalValue,
                              "value": finalValue,
                              "unit": unit,
                              "disabled": disabled,
                              "info": itemInfo,
                              "from": from,
                              "to": to,
                              "rangeType": rangeType,
                              "checkedValue": checkedValue,
                              "uncheckedValue": uncheckedValue,
                              "checked": checked});
            }

            /*
             * Process all of the ground station settings received over UDP, which happens on the C++
             * side (in openhdsettings.cpp)
             *
             */
            var allSettings = openHDSettings.getAllSettings();

            for (var setting in allSettings) {
                /*
                 * Here we distribute the incoming settings key/value pairs to the ListModel for each tab.
                 *
                 * If a particular setting is found in one of the mappings, we give it special treatment
                 * by adding a nicer title, handling any value mapping that may be required, and place it
                 * in a particular tab on the settings panel for organization and ease of use.
                 *
                 */

                if (settingsMap.blacklistMap[setting] !== undefined) {
                    continue;
                }

                var disabled = false;
                if (settingsMap.disabledMap[setting] !== undefined) {
                    disabled = true;
                }

                var initialValue = allSettings[setting];
                if (settingsMap.generalSettingsMap[setting] !== undefined) {
                    _process(setting, initialValue, generalSettingsModel, settingsMap.generalSettingsMap, disabled);
                } else if (settingsMap.radioSettingsMap[setting] !== undefined) {
                    _process(setting, initialValue, radioSettingsModel, settingsMap.radioSettingsMap, disabled);
                } else if (settingsMap.cameraSettingsMap[setting] !== undefined) {
                    _process(setting, initialValue, cameraSettingsModel, settingsMap.cameraSettingsMap, disabled);
                } else if (settingsMap.ethernetSettingsMap[setting] !== undefined) {
                    _process(setting, initialValue, ethernetSettingsModel, settingsMap.ethernetSettingsMap, disabled);
                } else {
                    /* setting not found in any mapping so add it to the "other" tab as-is, no processing
                       of any kind. This guarantees that newly added settings are never missing from the app.
                       */
                    otherSettingsModel.append({"title": setting,
                                               "setting": setting,
                                               "itemType": "string",
                                               "value": String(allSettings[setting]),
                                               "originalValue": String(allSettings[setting]),
                                               "disabled": disabled,
                                               "info": "No additional information available, check the Open.HD wiki"});
                }
            }
        }
    }

    function configureWithSetting(key, value) {
        if (key === "FORWARD_STREAM") {
            settings.enable_rtp = (value === "rtp");
        }

        if (key === "VIDEO_UDP_PORT") {
            settings.main_video_port = value;
        }

        if (key === "VIDEO_UDP_PORT2") {
            settings.pip_video_port = value;
        }
    }

    function writeRemoteSettings() {
        var remoteSettings = {};

        function _process(model, mapping) {
            for(var index = 0; index < model.count; index++) {
                var setting = model.get(index);

                var key = setting["setting"];
                var originalValue = setting["originalValue"];
                var newValue = setting["value"];

                 // skip saving any settings the user hasn't actually changed
                if (originalValue === newValue) {
                    continue;
                }
                /* Update the originalValue in the model itself.

                   This is a quick hack, a better solution would be to only update the originalValue
                   property once the setting actually saves
                */
                model.get(index).originalValue = newValue;

                // by default we pass through the value as-is, only map to another type if needed
                var finalValue = newValue;

                /* map bool values back to their expected representation for each setting, because
                   it's not the same for all of them
                */
                if (mapping !== undefined && mapping[setting.setting] !== undefined) {
                    var itemType   = mapping[setting.setting]["itemType"];
                    var trueValue  = mapping[setting.setting]["trueValue"];
                    var falseValue = mapping[setting.setting]["falseValue"];
                    var valueType = mapping[setting.setting]["valueType"];

                    if (itemType === "bool") {
                        if (newValue) {
                            finalValue = trueValue;
                        } else {
                            finalValue = falseValue;
                        }
                    }
                    if (valueType === "hex4") {
                        var hexValue4 = newValue.toString(16)
                        if (newValue < 16){
                            finalValue = "0x0" + hexValue4.toUpperCase();
                        } else if (newValue < 256){
                            finalValue = "0x" + hexValue4.toUpperCase();
                        } else {
                            finalValue = "0" + hexValue4.toUpperCase();
                        }
                    } else if(valueType === "hex3"){
                        var hexValue3 = newValue.toString(16);
                        finalValue = "0x" + hexValue3.toUpperCase();
                    }
                }
                remoteSettings[key] = finalValue;
            }
        }
        _process(generalSettingsModel,   settingsMap.generalSettingsMap);
        _process(radioSettingsModel,     settingsMap.radioSettingsMap);
        _process(cameraSettingsModel,     settingsMap.cameraSettingsMap);
        _process(ethernetSettingsModel,        settingsMap.ethernetSettingsMap);

        _process(otherSettingsModel, {});

        openHDSettings.saveSettings(remoteSettings);
    }

}

/*##^##
Designer {
    D{i:0;autoSize:true;height:480;width:640}
}
##^##*/
