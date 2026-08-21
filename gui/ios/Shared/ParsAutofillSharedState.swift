import AuthenticationServices
import Foundation
import Security

struct ParsAutofillStoredState: Codable {
  let enabled: Bool
  let configPath: String
  let indexPath: String
  let storeRoot: String?
  let generation: String?
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
      throw autofillError(code: 2, message: "App group container is unavailable")
    }
    guard let storeRoot, !storeRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw autofillError(code: 3, message: "A ready password store is required")
    }
    let sourceIndexURL = URL(fileURLWithPath: indexPath)
    guard FileManager.default.fileExists(atPath: sourceIndexURL.path) else {
      throw autofillError(code: 4, message: "An explicit Autofill rebuild is required")
    }
    try FileManager.default.createDirectory(
      at: containerURL,
      withIntermediateDirectories: true)

    let sharedIndexURL = containerURL.appendingPathComponent(indexFileName)
    if FileManager.default.fileExists(atPath: sharedIndexURL.path) {
      try FileManager.default.removeItem(at: sharedIndexURL)
    }
    try FileManager.default.copyItem(at: sourceIndexURL, to: sharedIndexURL)

    let state = ParsAutofillStoredState(
      enabled: true,
      configPath: configPath,
      indexPath: sharedIndexURL.path,
      storeRoot: storeRoot,
      generation: UUID().uuidString)
    let stateData = try JSONEncoder().encode(state)
    try stateData.write(
      to: containerURL.appendingPathComponent(stateFileName),
      options: .atomic)

    if let passphrase, !passphrase.isEmpty {
      try savePassphrase(passphrase)
    } else {
      let status = deletePassphrase()
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw autofillError(code: 5, message: "Autofill authorization could not be cleared")
      }
    }
  }

  typealias IdentityRemoval = (@escaping (Bool, Error?) -> Void) -> Void

  static func clear(completion: @escaping (Result<Void, Error>) -> Void) {
    performClear(
      containerURL: containerURL(),
      deleteAuthorization: { deletePassphrase() },
      removeIdentities: { callback in
        ASCredentialIdentityStore.shared.removeAllCredentialIdentities(callback)
      },
      completion: completion)
  }

  static func performClear(
    containerURL: URL?,
    deleteAuthorization: () -> OSStatus,
    removeIdentities: @escaping IdentityRemoval,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    var firstFailure: Error?
    if let containerURL {
      do {
        try FileManager.default.createDirectory(
          at: containerURL,
          withIntermediateDirectories: true)
      } catch {
        firstFailure = error
      }
      let stateURL = containerURL.appendingPathComponent(stateFileName)
      let indexURL = containerURL.appendingPathComponent(indexFileName)
      do {
        try persistDisabledState(containerURL: containerURL)
      } catch {
        firstFailure = firstFailure ?? error
        // A missing state is also disabled; try it even when tombstone persistence failed.
        do {
          if FileManager.default.fileExists(atPath: stateURL.path) {
            try FileManager.default.removeItem(at: stateURL)
          }
        } catch {
          firstFailure = firstFailure ?? error
        }
      }
      do {
        if FileManager.default.fileExists(atPath: indexURL.path) {
          try FileManager.default.removeItem(at: indexURL)
        }
      } catch {
        firstFailure = firstFailure ?? error
      }
    } else {
      firstFailure = autofillError(code: 6, message: "App group container is unavailable")
    }

    let keychainStatus = deleteAuthorization()
    if keychainStatus != errSecSuccess && keychainStatus != errSecItemNotFound,
      firstFailure == nil
    {
      firstFailure = autofillError(
        code: 7,
        message: "Autofill authorization could not be cleared")
    }

    removeIdentities { success, error in
      var failure = firstFailure
      if !success && failure == nil {
        failure = error ?? autofillError(
          code: 8,
          message: "Credential identities could not be removed")
      }
      if let containerURL {
        do {
          // Defense in depth: this must be the final shared-state write.
          try persistDisabledState(containerURL: containerURL)
        } catch {
          failure = failure ?? error
        }
      }
      DispatchQueue.main.async {
        if let failure {
          completion(.failure(failure))
        } else {
          completion(.success(()))
        }
      }
    }
  }

  private static func persistDisabledState(containerURL: URL) throws {
    let indexURL = containerURL.appendingPathComponent(indexFileName)
    let tombstone = ParsAutofillStoredState(
      enabled: false,
      configPath: "",
      indexPath: indexURL.path,
      storeRoot: nil,
      generation: nil)
    try JSONEncoder().encode(tombstone).write(
      to: containerURL.appendingPathComponent(stateFileName),
      options: .atomic)
  }

  static func loadState() -> ParsAutofillStoredState? {
    guard let containerURL = containerURL() else { return nil }
    let url = containerURL.appendingPathComponent(stateFileName)
    guard let data = try? Data(contentsOf: url),
      let state = try? JSONDecoder().decode(ParsAutofillStoredState.self, from: data),
      state.enabled,
      state.generation?.isEmpty == false
    else { return nil }
    return state
  }

  static func loadIndex() -> ParsAutofillIndex? {
    guard let state = loadState(),
      let data = try? Data(contentsOf: URL(fileURLWithPath: state.indexPath))
    else {
      return nil
    }
    return try? JSONDecoder().decode(ParsAutofillIndex.self, from: data)
  }

  static func loadPassphrase() -> String? {
    guard loadState() != nil else { return nil }
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
    guard let state = loadState(),
      let data = try? Data(contentsOf: URL(fileURLWithPath: state.indexPath)),
      let index = try? JSONDecoder().decode(ParsAutofillIndex.self, from: data)
    else {
      ASCredentialIdentityStore.shared.removeAllCredentialIdentities { success, _ in
        completion?(success)
      }
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
            recordIdentifier: recordIdentifier(
              path: entry.path,
              generation: state.generation!)))
      }
    }
    ASCredentialIdentityStore.shared.replaceCredentialIdentities(with: identities) { success, _ in
      completion?(success)
    }
  }

  static func recordIdentifier(path: String, generation: String) -> String {
    "\(generation)\u{0}\(path)"
  }

  static func parseRecordIdentifier(_ value: String) -> (generation: String, path: String)? {
    guard let separator = value.firstIndex(of: "\u{0}"), separator != value.startIndex else {
      return nil
    }
    let pathStart = value.index(after: separator)
    guard pathStart < value.endIndex else { return nil }
    return (String(value[..<separator]), String(value[pathStart...]))
  }

  static func samePublication(
    _ expected: ParsAutofillStoredState,
    _ current: ParsAutofillStoredState?
  ) -> Bool {
    guard let current else { return false }
    return current.enabled
      && current.generation == expected.generation
      && current.storeRoot == expected.storeRoot
      && current.indexPath == expected.indexPath
  }

  static func performIfCurrent<T>(
    generation: String,
    load: () -> ParsAutofillStoredState?,
    operation: () -> T?
  ) -> T? {
    guard let before = load(), before.generation == generation else { return nil }
    guard let result = operation(), samePublication(before, load()) else { return nil }
    return result
  }

  private static func isHostLike(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.contains(".") && !trimmed.contains(where: { $0.isWhitespace })
  }

  private static func savePassphrase(_ passphrase: String) throws {
    let deleteStatus = deletePassphrase()
    guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
      throw autofillError(code: 9, message: "Existing Autofill authorization could not be replaced")
    }
    var query = keychainQuery()
    query[kSecValueData as String] = Data(passphrase.utf8)
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(query as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      throw autofillError(code: 10, message: "Autofill authorization could not be saved")
    }
  }

  @discardableResult
  private static func deletePassphrase() -> OSStatus {
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

  private static func autofillError(code: Int, message: String) -> NSError {
    NSError(
      domain: "ParsAutofill",
      code: code,
      userInfo: [NSLocalizedDescriptionKey: message])
  }
}
