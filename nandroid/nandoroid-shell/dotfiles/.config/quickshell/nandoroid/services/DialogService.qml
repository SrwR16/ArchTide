pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
    id: root

    property bool active: false
    property string titleText: ""
    property string messageText: ""
    property string confirmText: I18nService.tr("OK")
    property string cancelText: I18nService.tr("Cancel")
    property string iconText: "warning"
    property bool isDestructive: false

    property var _confirmCallback: null
    property var _cancelCallback: null

    function requestConfirmation(options, onConfirm, onCancel) {
        root.titleText = options.titleText || I18nService.tr("Are you sure?");
        root.messageText = options.messageText || I18nService.tr("This action cannot be undone.");
        root.confirmText = options.confirmText || I18nService.tr("OK");
        root.cancelText = options.cancelText || I18nService.tr("Cancel");
        root.iconText = options.iconText !== undefined ? options.iconText : "warning";
        root.isDestructive = options.isDestructive !== undefined ? options.isDestructive : false;
        
        root._confirmCallback = onConfirm;
        root._cancelCallback = onCancel;
        
        root.active = true;
    }

    function submit() {
        if (!root.active) return;
        root.active = false;
        if (root._confirmCallback) {
            root._confirmCallback();
        }
    }

    function cancel() {
        if (!root.active) return;
        root.active = false;
        if (root._cancelCallback) {
            root._cancelCallback();
        }
    }
}
