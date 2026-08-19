import AuthenticationServices
import Foundation
import Security

struct ParsAutofillStoredState: Codable {
  let configPath: String
  let indexPath: String
  let storeRoot: String?
}

struct ParsAutofillIndex: Codable {
  let entries: [ParsAutofillIndexEntry]
}

struct ParsAutofillIndexEntry: Codable {
  let path: String
  let displayName: String
  let serviceName: String?
  let username: String
  let pathWebsite: String?
  let enrichedWebsites: [String]

  enum CodingKeys: String, CodingKey {
    case path
    case displayName = "display_name"
    case serviceName = "service_name"
    case username
    case pathWebsite = "path_website"
    case enrichedWebsites = "enriched_websites"
  }
}

enum ParsAutofillSharedState {
  static let appGroupIdentifier = "group.com.example.parsGui"
  private static let stateFileName = "autofill-state.json"
  private static let indexFileName = "autofill.json"
  private static let keychainService = "top.vollate.pars_gui.autofill"
  private static let keychainAccount = "pgp-passphrase"
  private static let keychainAccessGroupInfoKey = "ParsKeychainAccessGroup"

  static func containerURL() -> URL? {
    FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier)
  }

  static func supportDirectoryURL() throws -> URL {
    guard let containerURL = containerURL() else {
      throw NSError(
        domain: "ParsAutofill",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "App group container is unavailable"])
    }
    let support = containerURL.appendingPathComponent("Support", isDirectory: true)
    try FileManager.default.createDirectory(
      at: support,
      withIntermediateDirectories: true)
    return support
  }

  static func publish(
    configPath: String,
    indexPath: String,
    storeRoot: String?,
    passphrase: String?
  ) throws {
    guard let containerURL = containerURL() else {
      throw NSError(
        domain: "ParsAutofill",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "App group container is unavailable"])
    }
    try FileManager.default.createDirectory(
      at: containerURL,
      withIntermediateDirectories: true)

    let sharedIndexURL = containerURL.appendingPathComponent(indexFileName)
    let sourceIndexURL = URL(fileURLWithPath: indexPath)
    if FileManager.default.fileExists(atPath: sourceIndexURL.path) {
      if FileManager.default.fileExists(atPath: sharedIndexURL.path) {
        try FileManager.default.removeItem(at: sharedIndexURL)
      }
      try FileManager.default.copyItem(at: sourceIndexURL, to: sharedIndexURL)
    }

    let state = ParsAutofillStoredState(
      configPath: configPath,
      indexPath: sharedIndexURL.path,
      storeRoot: storeRoot)
    let stateData = try JSONEncoder().encode(state)
    try stateData.write(
      to: containerURL.appendingPathComponent(stateFileName),
      options: .atomic)

    if let passphrase, !passphrase.isEmpty {
      savePassphrase(passphrase)
    } else {
      deletePassphrase()
    }
  }

  static func clear() {
    guard let containerURL = containerURL() else { return }
    try? FileManager.default.removeItem(at: containerURL.appendingPathComponent(stateFileName))
    try? FileManager.default.removeItem(at: containerURL.appendingPathComponent(indexFileName))
    deletePassphrase()
    ASCredentialIdentityStore.shared.removeAllCredentialIdentities { _, _ in }
  }

  static func loadState() -> ParsAutofillStoredState? {
    guard let containerURL = containerURL() else { return nil }
    let url = containerURL.appendingPathComponent(stateFileName)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(ParsAutofillStoredState.self, from: data)
  }

  static func loadIndex() -> ParsAutofillIndex? {
    let path = loadState()?.indexPath ?? containerURL()?.appendingPathComponent(indexFileName).path
    guard let path, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
      return nil
    }
    return try? JSONDecoder().decode(ParsAutofillIndex.self, from: data)
  }

  static func loadPassphrase() -> String? {
    var query = keychainQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  static func syncCredentialIdentities(completion: ((Bool) -> Void)? = nil) {
    guard let index = loadIndex() else {
      completion?(false)
      return
    }
    var seen = Set<String>()
    var identities: [ASPasswordCredentialIdentity] = []
    for entry in index.entries {
      var websites = entry.enrichedWebsites
      if let pathWebsite = entry.pathWebsite {
        websites.insert(pathWebsite, at: 0)
      }
      for website in websites {
        let key = "\(website)\u{0}\(entry.path)"
        guard isHostLike(website), seen.insert(key).inserted else { continue }
        identities.append(
          ASPasswordCredentialIdentity(
            serviceIdentifier: ASCredentialServiceIdentifier(
              identifier: website,
              type: .domain),
            user: entry.username,
            recordIdentifier: entry.path))
      }
    }
    ASCredentialIdentityStore.shared.replaceCredentialIdentities(with: identities) { success, _ in
      completion?(success)
    }
  }

  private static func isHostLike(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.contains(".") && !trimmed.contains(where: { $0.isWhitespace })
  }

  private static func savePassphrase(_ passphrase: String) {
    deletePassphrase()
    var query = keychainQuery()
    query[kSecValueData as String] = Data(passphrase.utf8)
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(query as CFDictionary, nil)
  }

  private static func deletePassphrase() {
    SecItemDelete(keychainQuery() as CFDictionary)
  }

  private static func keychainQuery() -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
    ]
    if let accessGroup = keychainAccessGroup() {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    return query
  }

  private static func keychainAccessGroup() -> String? {
    guard
      let value = Bundle.main.object(forInfoDictionaryKey: keychainAccessGroupInfoKey) as? String,
      !value.isEmpty,
      !value.contains("$(")
    else {
      return nil
    }
    return value
  }
}
