import Carbon.HIToolbox
import Foundation

@MainActor
final class TaskLightGlobalShortcutController {
    private var eventHandler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private let togglePanel: () -> Void
    private let toggleExpanded: () -> Void

    init(togglePanel: @escaping () -> Void, toggleExpanded: @escaping () -> Void) {
        self.togglePanel = togglePanel
        self.toggleExpanded = toggleExpanded
        install()
    }

    deinit {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private func install() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let controller = Unmanaged<TaskLightGlobalShortcutController>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in controller.handle(hotKeyID.id) }
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandler
        )
        register(id: 1, keyCode: UInt32(kVK_ANSI_T))
        register(id: 2, keyCode: UInt32(kVK_ANSI_R))
    }

    private func register(id: UInt32, keyCode: UInt32) {
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: OSType(0x3636544C), id: id)
        let modifiers = UInt32(cmdKey | optionKey)
        if RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &reference) == noErr,
           let reference {
            hotKeys.append(reference)
        }
    }

    private func handle(_ id: UInt32) {
        switch id {
        case 1: togglePanel()
        case 2: toggleExpanded()
        default: break
        }
    }
}
