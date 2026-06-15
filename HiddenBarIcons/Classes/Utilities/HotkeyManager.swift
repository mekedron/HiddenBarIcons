//
//  HotkeyManager.swift
//  HiddenBarIcons
//

import Carbon
import Foundation

class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let callback: () -> Void

    private static var sharedInstance: HotkeyManager?

    init(callback: @escaping () -> Void) {
        self.callback = callback
        HotkeyManager.sharedInstance = self
        self.registerHotkey()
    }

    deinit {
        unregisterHotkey()
    }

    private func registerHotkey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }

            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                UInt32(kEventParamDirectObject),
                UInt32(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            if err == noErr, hotKeyID.id == 1 {
                DispatchQueue.main.async {
                    HotkeyManager.sharedInstance?.callback()
                }
            }

            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &self.eventHandlerRef
        )

        // CMD + Option + B
        // kVK_ANSI_B = 11
        // cmdKey = 256 (0x100)
        // optionKey = 2048 (0x800)
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x4842_4943), // "HBIC" as FourCharCode
            id: 1
        )

        let modifiers = UInt32(cmdKey | optionKey)

        RegisterEventHotKey(
            UInt32(kVK_ANSI_B),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &self.hotKeyRef
        )
    }

    private func unregisterHotkey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}
