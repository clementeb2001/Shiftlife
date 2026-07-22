import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Principal view controller for the "Teilen → ShiftLife" share extension.
/// Pulls the shared text out of the extension item, then hosts a SwiftUI
/// confirmation screen that shows the detected Bereitschaft periods.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        loadSharedText { [weak self] text in
            DispatchQueue.main.async { self?.embed(text ?? "") }
        }
    }

    private func embed(_ text: String) {
        let root = ShareRootView(
            text: text,
            onDone: { [weak self] in self?.finish() },
            onCancel: { [weak self] in self?.cancel() })
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func finish() { extensionContext?.completeRequest(returningItems: nil) }
    private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "ShiftLife", code: 0))
    }

    /// Tries the common text type identifiers, then falls back to the item's
    /// attributed content text.
    private func loadSharedText(completion: @escaping (String?) -> Void) {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            completion(nil); return
        }
        let types = [UTType.plainText.identifier, UTType.utf8PlainText.identifier, UTType.text.identifier]
        for item in items {
            for provider in item.attachments ?? [] {
                if let type = types.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) {
                    provider.loadItem(forTypeIdentifier: type, options: nil) { data, _ in
                        let text = (data as? String)
                            ?? (data as? NSAttributedString)?.string
                            ?? (data as? Data).flatMap { String(data: $0, encoding: .utf8) }
                        completion(text)
                    }
                    return
                }
            }
        }
        if let attributed = items.first?.attributedContentText?.string {
            completion(attributed); return
        }
        completion(nil)
    }
}
