import AuthenticationServices
import LocalAuthentication
import UIKit

final class CredentialProviderViewController: ASCredentialProviderViewController {
  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private var candidates: [ParsAutofillIosCandidate] = []
  private var candidateGenerations: [String: String] = [:]

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

  private func complete(path: String, generation: String) {
    guard let credential: ParsAutofillIosCredential = ParsAutofillSharedState.performIfCurrent(
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
          passphrase: ParsAutofillSharedState.loadPassphrase())
      })
    else {
      cancel(code: .credentialIdentityNotFound)
      return
    }
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
