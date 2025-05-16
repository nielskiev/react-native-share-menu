//
//  ShareViewController.swift
//  RNShareMenu
//
//  THIS FILE IS MANAGED BY YOUR FORK — copy/paste into your plugin’s `ios/ShareViewController.swift`.
//  Updated to hand off immediately on iOS 18+.
//

import UIKit
import Social
import UniformTypeIdentifiers
import RNShareMenu

// Allow UIApplication.shared.open from an extension
@available(iOSApplicationExtension, unavailable)
class ShareViewController: SLComposeServiceViewController {

  // MARK: – Keys from Info.plist
  private let hostAppIdKey = HOST_APP_IDENTIFIER_INFO_PLIST_KEY
  private let hostAppSchemeKey = HOST_URL_SCHEME_INFO_PLIST_KEY

  // MARK: – Instance state
  private var hostAppId: String!
  private var hostAppUrlScheme: String!
  private var sharedItems: [[String: Any]] = []

  // MARK: – Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()

    // 1. Read Info.plist entries
    guard let bundleID = Bundle.main.object(forInfoDictionaryKey: hostAppIdKey) as? String else {
      cancelRequest(withError: NO_INFO_PLIST_INDENTIFIER_ERROR)
      return
    }
    hostAppId = bundleID

    guard let scheme = Bundle.main.object(forInfoDictionaryKey: hostAppSchemeKey) as? String else {
      cancelRequest(withError: NO_INFO_PLIST_URL_SCHEME_ERROR)
      return
    }
    hostAppUrlScheme = scheme

    // 2. Grab the incoming items
    guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
      cancelRequest(withError: COULD_NOT_FIND_URL_ERROR)
      return
    }

    // 3. Immediately process & hand off
    handlePost(items)
  }

  // Remove didSelectPost + configurationItems entirely
  // override func didSelectPost() { /* no-op */ }
  // override func configurationItems() -> [Any]! { return [] }

  // MARK: – Main logic

  private func handlePost(_ items: [NSExtensionItem]) {
    DispatchQueue.global(qos: .userInitiated).async {
      // 1. UserDefaults in App Group
      guard let userDefaults = UserDefaults(suiteName: "group.\(self.hostAppId!)") else {
        self.cancelRequest(withError: NO_APP_GROUP_ERROR)
        return
      }

      // 2. Iterate attachments
      let sem = DispatchSemaphore(value: 0)
      for item in items {
        guard let providers = item.attachments else {
          self.cancelRequest(withError: COULD_NOT_FIND_STRING_ERROR)
          return
        }
        for provider in providers {
          if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            self.storeText(provider, sem)
          }
          else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            self.storeFile(provider, sem)
          }
          else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            self.storeUrl(provider, sem)
          }
          else {
            // maybe handle other UTTypes...
            sem.signal()
          }
          sem.wait()
        }
      }

      // 3. Persist & open host
      userDefaults.set(self.sharedItems, forKey: USER_DEFAULTS_KEY)
      userDefaults.synchronize()
      self.openHostApp()
    }
  }

  private func storeText(_ provider: NSItemProvider, _ sem: DispatchSemaphore) {
    print("Store Text")

    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, _ in
      defer { sem.signal() }
      if let txt = data as? String {
        self.sharedItems.append([DATA_KEY: txt, MIME_TYPE_KEY: "text/plain"])
      }
    }
  }

  private func storeFile(_ provider: NSItemProvider, _ sem: DispatchSemaphore) {
    print("Store File")

    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
      defer { sem.signal() }
      guard let incomingURL = data as? URL,
            let hostId = self.hostAppId,
            let container = FileManager.default
              .containerURL(forSecurityApplicationGroupIdentifier: "group.\(hostId)")
      else {
        print("⚠️ storeFile: bad input or missing App Group")
        return
      }

      let didStart = incomingURL.startAccessingSecurityScopedResource()
      defer { if didStart { incomingURL.stopAccessingSecurityScopedResource() } }

      let filename = UUID().uuidString + "." + incomingURL.pathExtension
      let destURL = container.appendingPathComponent(filename)
      try? FileManager.default.removeItem(at: destURL)

      do {
        try FileManager.default.copyItem(at: incomingURL, to: destURL)
        let mime = destURL.extractMimeType()
        self.sharedItems.append([
          DATA_KEY: destURL.absoluteString,
          MIME_TYPE_KEY: mime,
          "fileName": incomingURL.lastPathComponent
        ])
      } catch {
        print("❌ storeFile copy failed:", error)
      }
    }
  }

  private func storeUrl(_ provider: NSItemProvider, _ sem: DispatchSemaphore) {
    print("Store URL")

    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, _ in
      defer { sem.signal() }
      guard let url = data as? URL else {
        print("⚠️ storeUrl: not a URL")
        return
      }

      if url.isFileURL {
        // treat exactly like storeFile but coordinate for safety
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: nil) { coordURL in
          guard let hostId = self.hostAppId,
                let container = FileManager.default
                  .containerURL(forSecurityApplicationGroupIdentifier: "group.\(hostId)")
          else {
            print("⚠️ storeUrl: missing App Group")
            return
          }

          let filename = UUID().uuidString + "." + coordURL.pathExtension
          let destURL = container.appendingPathComponent(filename)
          try? FileManager.default.removeItem(at: destURL)

          do {
            try FileManager.default.copyItem(at: coordURL, to: destURL)
            let mime = destURL.extractMimeType()
            self.sharedItems.append([
              DATA_KEY: destURL.absoluteString,
              MIME_TYPE_KEY: mime,
              "fileName": coordURL.lastPathComponent
            ])
          } catch {
            print("❌ storeUrl copy failed:", error)
          }
        }
      } else {
        // a regular HTTP/HTTPS/etc URL – just forward it
        self.sharedItems.append([
          DATA_KEY: url.absoluteString,
          MIME_TYPE_KEY: "text/plain"
        ])
      }
    }
  }

  private func openHostApp() {
    guard let url = URL(string: hostAppUrlScheme) else {
      cancelRequest(withError: NO_INFO_PLIST_URL_SCHEME_ERROR)
      return
    }
    UIApplication.shared.open(url, options: [:]) { _ in
      self.completeRequest()
    }
  }

  // MARK: – Finish up

  private func completeRequest() {
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }

  private func cancelRequest(withError error: String) {
    print("ShareExtension error:", error)
    extensionContext?.cancelRequest(withError: NSError(domain: error, code: 0, userInfo: nil))
  }
}
