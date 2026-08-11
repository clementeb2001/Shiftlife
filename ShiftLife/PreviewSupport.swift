import SwiftUI

#if DEBUG
extension AppStore {
    /// A ready-to-use in-memory store with sample data + assist defaults, for
    /// Xcode Previews (Canvas). Never touches disk or iCloud.
    static var preview: AppStore {
        let store = AppStore(inMemory: true)
        store.ensureAssistDefaults()
        return store
    }
}
#endif
