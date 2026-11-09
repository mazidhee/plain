import Carbon
import Foundation

/// A system-wide hotkey through Carbon's RegisterEventHotKey (no Accessibility permission needed).
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private let id: UInt32

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.actions[id] = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if let action = HotKey.actions[hk.id] { DispatchQueue.main.async(execute: action) }
            return noErr
        }, 1, &spec, nil, &handler)
        guard status == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x504C_4E54), id: id) // "PLNT"
        let reg = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard reg == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        HotKey.actions[id] = nil
    }
}
