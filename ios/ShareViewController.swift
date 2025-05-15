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
          } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            self.storeUrl(provider, sem)
          } else {
            self.storeFile(provider, sem)
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

  private func storeUrl(_ provider: NSItemProvider, _ sem: DispatchSemaphore) {
    print("Store URL")

    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, _ in
      defer { sem.signal() }
      if let url = data as? URL {
        self.sharedItems.append([DATA_KEY: url.absoluteString, MIME_TYPE_KEY: "text/plain"])
      }
    }
  }

  private func storeFile(_ provider: NSItemProvider, _ sem: DispatchSemaphore) {
    print("Store File")

    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
      defer { sem.signal() }
      guard let url = data as? URL,
            let hostId = self.hostAppId,
            let container = FileManager.default
              .containerURL(forSecurityApplicationGroupIdentifier: "group.\(hostId)")
      else { return }

      let filename = UUID().uuidString + "." + url.pathExtension
      print("Filename: " + filename);

      let dest = container.appendingPathComponent(filename)
      try? FileManager.default.removeItem(at: dest)
      do {
        try FileManager.default.copyItem(at: url, to: dest)
        let mime = url.extractMimeType()
        self.sharedItems.append([
          DATA_KEY: dest.absoluteString,
          MIME_TYPE_KEY: mime,
          "fileName": url.lastPathComponent
        ])
      } catch {
        print("Copy failed:", error)
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
