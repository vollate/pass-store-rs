import AuthenticationServices
import LocalAuthentication
import UIKit

final class CredentialProviderViewController: ASCredentialProviderViewController {
  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private var candidates: [ParsAutofillIosCandidate] = []
  private var candidateGenerations: [String: String] = [:]
  private var passphraseAttempts = 0
  private static let maxPassphraseAttempts = 3

  override func viewDidLoad() {
    super.viewDidLoad()
    tableView.dataSource = self
    tableView.delegate = self
    tableView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(tableView)
    NSLayoutConstraint.activate([
      tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      tableView.topAnchor.constraint(equalTo: view.topAnchor),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }

  override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
    candidates = candidatesFor(serviceIdentifiers: serviceIdentifiers)
    tableView.reloadData()
    if candidates.isEmpty {
      cancel(code: .credentialIdentityNotFound)
    }
  }

  override func provideCredentialWithoutUserInteraction(
    for credentialIdentity: ASPasswordCredentialIdentity
  ) {
    cancel(code: .userInteractionRequired)
  }

  override func prepareInterfaceToProvideCredential(
    for credentialIdentity: ASPasswordCredentialIdentity
  ) {
    guard let identifier = credentialIdentity.recordIdentifier,
      let parsed = ParsAutofillSharedState.parseRecordIdentifier(identifier)
    else {
      cancel(code: .credentialIdentityNotFound)
      return
    }
    authenticateAndComplete(path: parsed.path, generation: parsed.generation)
  }

  private func candidatesFor(
    serviceIdentifiers: [ASCredentialServiceIdentifier]
  ) -> [ParsAutofillIosCandidate] {
    guard let state = ParsAutofillSharedState.loadState(),
      let generation = state.generation
    else { return [] }
    candidateGenerations.removeAll()
    var seen = Set<String>()
    var result: [ParsAutofillIosCandidate] = []
    for service in serviceIdentifiers {
      let website = service.type == .domain || service.type == .URL ? service.identifier : nil
      let candidates = ParsAutofillSharedState.performIfCurrent(
        generation: generation,
        load: { ParsAutofillSharedState.loadState() },
        operation: {
          ParsAutofillNative.queryCandidates(
            indexPath: state.indexPath,
            website: website,
            query: service.identifier,
            limit: 10)
        }) ?? []
      for candidate in candidates where seen.insert(candidate.path).inserted {
        candidateGenerations[candidate.path] = generation
        result.append(candidate)
      }
    }
    return result
  }

  private func authenticateAndComplete(path: String, generation: String) {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      cancel(code: .failed)
      return
    }
    context.evaluatePolicy(
      .deviceOwnerAuthentication,
      localizedReason: NSLocalizedString(
        "autofill_authentication_reason",
        comment: "Reason shown before filling the selected password")
    ) { [weak self] success, _ in
      DispatchQueue.main.async {
        guard success else {
          self?.cancel(code: .userCanceled)
          return
        }
        self?.complete(path: path, generation: generation)
      }
    }
  }

  private func complete(path: String, generation: String, passphrase: String? = nil) {
    let resolution: ParsAutofillIosResolution? = ParsAutofillSharedState.performIfCurrent(
      generation: generation,
      load: { ParsAutofillSharedState.loadState() },
      operation: {
        guard let state = ParsAutofillSharedState.loadState(), let root = state.storeRoot else {
          return nil
        }
        return ParsAutofillNative.resolveCredential(
          configPath: state.configPath,
          indexPath: state.indexPath,
          root: root,
          path: path,
          passphrase: passphrase ?? ParsAutofillSharedState.loadPassphrase())
      })
    guard let resolution else {
      cancel(code: .credentialIdentityNotFound)
      return
    }
    switch resolution {
    case .resolved(let credential):
      deliver(credential: credential, generation: generation)
    case .passphraseRequired:
      promptForPassphrase(path: path, generation: generation, rejected: passphrase != nil)
    case .unavailable:
      cancel(code: .credentialIdentityNotFound)
    }
  }

  /// Asks for the PGP passphrase when none was published, so Autofill still
  /// works without durable passphrase storage. Input is used for this single
  /// decryption and never persisted.
  private func promptForPassphrase(path: String, generation: String, rejected: Bool) {
    guard passphraseAttempts < Self.maxPassphraseAttempts else {
      cancel(code: .failed)
      return
    }
    passphraseAttempts += 1
    let message =
      rejected
      ? NSLocalizedString(
        "autofill_passphrase_rejected", comment: "Shown after a passphrase failed to decrypt")
      : NSLocalizedString(
        "autofill_passphrase_message", comment: "Explains why Pars needs the PGP passphrase")
    let alert = UIAlertController(
      title: NSLocalizedString(
        "autofill_passphrase_title", comment: "Title of the PGP passphrase prompt"),
      message: message,
      preferredStyle: .alert)
    alert.addTextField { field in
      field.isSecureTextEntry = true
      field.textContentType = .password
      field.placeholder = NSLocalizedString(
        "autofill_passphrase_hint", comment: "Placeholder of the PGP passphrase field")
    }
    alert.addAction(
      UIAlertAction(
        title: NSLocalizedString("autofill_cancel", comment: "Dismisses the passphrase prompt"),
        style: .cancel
      ) { [weak self] _ in
        self?.cancel(code: .userCanceled)
      })
    alert.addAction(
      UIAlertAction(
        title: NSLocalizedString("autofill_passphrase_unlock", comment: "Confirms the passphrase"),
        style: .default
      ) { [weak self] _ in
        self?.complete(
          path: path,
          generation: generation,
          passphrase: alert.textFields?.first?.text ?? "")
      })
    present(alert, animated: true)
  }

  private func deliver(credential: ParsAutofillIosCredential, generation: String) {
    let passwordCredential = ASPasswordCredential(
      user: credential.username,
      password: credential.password)
    let _: Bool? = ParsAutofillSharedState.performIfCurrent(
      generation: generation,
      load: { ParsAutofillSharedState.loadState() },
      operation: {
        guard let state = ParsAutofillSharedState.loadState() else { return nil }
        return ParsAutofillNative.recordCompletion(
          indexPath: state.indexPath,
          path: credential.path) ? true : nil
      })
    extensionContext.completeRequest(
      withSelectedCredential: passwordCredential,
      completionHandler: nil)
  }

  private func cancel(code: ASExtensionError.Code) {
    extensionContext.cancelRequest(
      withError: NSError(
        domain: ASExtensionErrorDomain,
        code: code.rawValue))
  }
}

extension CredentialProviderViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    candidates.count
  }

  func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    let candidate = candidates[indexPath.row]
    cell.textLabel?.text = candidate.displayName
    cell.detailTextLabel?.text = candidate.username
    cell.accessoryType = .disclosureIndicator
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    let path = candidates[indexPath.row].path
    guard let generation = candidateGenerations[path] else {
      cancel(code: .credentialIdentityNotFound)
      return
    }
    authenticateAndComplete(path: path, generation: generation)
  }
}
