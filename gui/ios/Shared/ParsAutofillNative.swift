import Foundation

@_silgen_name("pars_autofill_query_candidates_json")
private func parsAutofillQueryCandidatesJson(_ request: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

@_silgen_name("pars_autofill_resolve_credential_json")
private func parsAutofillResolveCredentialJson(_ request: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

@_silgen_name("pars_autofill_free_string")
private func parsAutofillFreeString(_ value: UnsafeMutablePointer<CChar>?)

struct ParsAutofillIosCandidate {
  let path: String
  let displayName: String
  let username: String?
  let matchValue: String
}

struct ParsAutofillIosCredential {
  let path: String
  let username: String?
  let password: String
}

enum ParsAutofillNative {
  static func queryCandidates(
    indexPath: String,
    website: String?,
    androidPackage: String? = nil,
    query: String?,
    limit: Int
  ) -> [ParsAutofillIosCandidate] {
    let request: [String: Any?] = [
      "indexPath": indexPath,
      "website": website,
      "androidPackage": androidPackage,
      "query": query,
      "limit": limit,
    ]
    guard let response = call(request: request, handler: parsAutofillQueryCandidatesJson),
      response["error"] is NSNull || response["error"] == nil,
      let rawCandidates = response["candidates"] as? [[String: Any]]
    else {
      return []
    }
    return rawCandidates.compactMap { candidate in
      guard let path = candidate["path"] as? String,
        let displayName = candidate["displayName"] as? String
      else {
        return nil
      }
      return ParsAutofillIosCandidate(
        path: path,
        displayName: displayName,
        username: candidate["username"] as? String,
        matchValue: candidate["matchValue"] as? String ?? "")
    }
  }

  static func resolveCredential(
    configPath: String,
    indexPath: String,
    root: String,
    path: String,
    passphrase: String?
  ) -> ParsAutofillIosCredential? {
    let request: [String: Any?] = [
      "configPath": configPath,
      "indexPath": indexPath,
      "root": root,
      "path": path,
      "pgpExecutable": nil,
      "passphrase": passphrase,
    ]
    guard let response = call(request: request, handler: parsAutofillResolveCredentialJson),
      response["error"] is NSNull || response["error"] == nil,
      let credential = response["credential"] as? [String: Any],
      let resolvedPath = credential["path"] as? String,
      let password = credential["password"] as? String
    else {
      return nil
    }
    return ParsAutofillIosCredential(
      path: resolvedPath,
      username: credential["username"] as? String,
      password: password)
  }

  private static func call(
    request: [String: Any?],
    handler: (UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
  ) -> [String: Any]? {
    let normalized = request.mapValues { value -> Any in value ?? NSNull() }
    guard JSONSerialization.isValidJSONObject(normalized),
      let data = try? JSONSerialization.data(withJSONObject: normalized),
      let json = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    return json.withCString { pointer in
      guard let raw = handler(pointer) else { return nil }
      defer { parsAutofillFreeString(raw) }
      let response = String(cString: raw)
      guard let responseData = response.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
      else {
        return nil
      }
      return object
    }
  }
}
