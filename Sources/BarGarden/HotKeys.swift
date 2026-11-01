import AppKit
import Carbon

@MainActor
final class HotKeys {
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private let callback: (UInt32) -> Void

    init(callback: @escaping (UInt32) -> Void) { self.callback = callback }

    func register() -> String? {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard result == noErr else { return result }
            let owner = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            let identifier = key.id
            Task { @MainActor in owner.callback(identifier) }
            return noErr
        }, 1, &event, context, &handler)
        guard status == noErr else { return "Could not install shortcut listener (\(status))." }
        for (id, code) in [(UInt32(1), UInt32(kVK_ANSI_B)), (UInt32(2), UInt32(kVK_Space))] {
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(code, UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x42475244, id: id), GetApplicationEventTarget(), 0, &reference)
            guard result == noErr, let reference else {
                unregister()
                return "Shortcut is in use or unavailable (\(result))."
            }
            references.append(reference)
        }
        return nil
    }

    func unregister() {
        for reference in references { UnregisterEventHotKey(reference) }
        references.removeAll()
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
}
