//
//  ShareViewController.swift
//  RNShareMenu
//
//  THIS FILE IS MANAGED BY YOUR FORK — copy/paste this into `ios/ShareViewController.swift` in your plugin repo.
//  Updated for iOS 18+ compatibility.
//

import UIKit
import Social
import UniformTypeIdentifiers
import RNShareMenu

// Allow UIApplication.shared.open from an extension
@available(iOSApplicationExtension, unavailable)
class ShareViewController: SLComposeServiceViewController {

  // MARK: - Properties

  private var hostAppId: String!
  private var hostAppUrlScheme: String!
  private var sharedItems: [[String: Any]] = []

  // MARK: - Lifecycle

  override func viewDidLoad() {
    super.viewDidLoad()

    // Read host app identifier + URL-scheme from Info.plist
    guard let bundle = Bundle.main.object(forInfoDictionaryKey: HOST_APP_IDENTIFIER_INFO_PLIST_KEY) as? String else {
      cancelRequest(withError: NO_INFO_PLIST_INDENTIFIER_ERROR)
      return
    }
    hostAppId = bundle

    guard let scheme = Bundle.main.object(forInfoDictionaryKey: HOST_URL_SCHEME_INFO_PLIST_KEY) as? String else {
      cancelRequest(withError: NO_INFO_PLIST_URL_SCHEME_ERROR)
      return
    }
    hostAppUrlScheme = scheme
  }

  // MARK: - SLComposeServiceViewController

  override func isContentValid() -> Bool {
    return true
  }

  override func didSelectPost() {
    guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
      cancelRequest(withError: COULD_NOT_FIND_STRING_ERROR)
      return
    }

    // If user entered text in the composer, pass it along as extraData
    let userText = contentText?.trimmingCharacters(in: .whitespacesAndNewlines)
    let extraData = (userText?.isEmpty == false)
      ? ["userInput": userText!]
      : nil

    handlePost(items, extraData: extraData)
  }

  override func configurationItems() -> [Any]! {
    return []
  }

  // MARK: - Main logic

  private func handlePost(_ items: [NSExtensionItem], extraData: [String: Any]? = nil) {
    DispatchQueue.global(qos: .userInitiated).async {
      // UserDefaults in App Group
      guard let userDefaults = UserDefaults(suiteName: "group.\(self.hostAppId!)") else {
        self.cancelRequest(withError: NO_APP_GROUP_ERROR)
        return
      }

      // Store any extra data
      if let extra = extraData {
        userDefaults.set(extra, forKey: USER_DEFAULTS_EXTRA_DATA_KEY)
      } else {
        userDefaults.removeObject(forKey: USER_DEFAULTS_EXTRA_DATA_KEY)
      }

      let semaphore = DispatchSemaphore(value: 0)

      // Iterate all attachment providers
      for item in items {
        guard let providers = item.attachments else {
          self.cancelRequest(withError: COULD_NOT_FIND_STRING_ERROR)
          return
        }

        for provider in providers {
          if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            self.storeText(provider, semaphore)
          } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            self.storeUrl(provider, semaphore)
          } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            self.storeFile(provider, semaphore)
          } else {
            // fallback: treat as data
            self.storeFile(provider, semaphore)
          }
          semaphore.wait()
        }
      }

      // Persist and wake up host
      userDefaults.set(self.sharedItems, forKey: USER_DEFAULTS_KEY)
      userDefaults.synchronize()
      self.openHostApp()
    }
  }

  private func storeText(_ provider: NSItemProvider, _ sem: DispatchSemaphore) {
    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, error in
      defer { sem.signal() }
      guard error == nil, let text = data as? String else { return }
      self.sharedItems.append([DATA_KEY: text, MIME_TYPE_KEY: "text/plain"])
    }
  }

  private func storeUrl(_ provider: NSItemProvider, _ sem: DispatchSemaphore) {
    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, error in
      defer { sem.signal() }
      guard error == nil, let url = data as? URL else { return }
      self.sharedItems.append([DATA_KEY: url.absoluteString, MIME_TYPE_KEY: "text/plain"])
    }
  }

  private func storeFile(_ provider: NSItemProvider, _ sem: DispatchSemaphore) {
    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
      defer { sem.signal() }
      guard error == nil else { return }

      // Prepare group container
      guard let hostId = self.hostAppId,
            let container = FileManager.default
              .containerURL(forSecurityApplicationGroupIdentifier: "group.\(hostId)")
      else { return }

      // Load URL or UIImage
      if let url = data as? URL {
        self.copyItem(url, to: container)
      } else if let img = data as? UIImage,
                let png = img.pngData() {
        let filename = "Image_\(UUID().uuidString).png"
        let dest = container.appendingPathComponent(filename)
        try? png.write(to: dest)
        self.sharedItems.append([
          DATA_KEY: dest.absoluteString,
          MIME_TYPE_KEY: "image/png",
          "fileName": filename
        ])
      }
    }
  }

  private func copyItem(_ src: URL, to container: URL) {
    let filename = src.lastPathComponent
    let dest = container.appendingPathComponent(filename)
    try? FileManager.default.removeItem(at: dest)
    do {
      try FileManager.default.copyItem(at: src, to: dest)
      let mime = src.extractMimeType()
      self.sharedItems.append([
        DATA_KEY: dest.absoluteString,
        MIME_TYPE_KEY: mime,
        "fileName": filename
      ])
    } catch {
      print("Copy failed:", error)
    }
  }

  private func openHostApp() {
    guard let scheme = URL(string: hostAppUrlScheme) else {
      cancelRequest(withError: NO_INFO_PLIST_URL_SCHEME_ERROR)
      return
    }
    UIApplication.shared.open(scheme, options: [:]) { _ in
      self.completeRequest()
    }
  }

  // MARK: - Complete / Cancel

  private func completeRequest() {
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }

  private func cancelRequest(withError error: String) {
    print("ShareExtension error:", error)
    extensionContext?.cancelRequest(withError: NSError(domain: error, code: 0, userInfo: nil))
  }
}
