import AuthenticationServices
import LocalAuthentication
import UIKit

final class CredentialProviderViewController: ASCredentialProviderViewController {
  private let tableView = UITableView(frame: .zero, style: .insetGrouped)
  private var candidates: [ParsAutofillIosCandidate] = []

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
    guard let path = credentialIdentity.recordIdentifier else {
      cancel(code: .credentialIdentityNotFound)
      return
    }
    authenticateAndComplete(path: path)
  }

  private func candidatesFor(
    serviceIdentifiers: [ASCredentialServiceIdentifier]
  ) -> [ParsAutofillIosCandidate] {
    guard let state = ParsAutofillSharedState.loadState() else { return [] }
    var seen = Set<String>()
    var result: [ParsAutofillIosCandidate] = []
    for service in serviceIdentifiers {
      let website = service.type == .domain || service.type == .URL ? service.identifier : nil
      let candidates = ParsAutofillNative.queryCandidates(
        indexPath: state.indexPath,
        website: website,
        query: service.identifier,
        limit: 10)
      for candidate in candidates where seen.insert(candidate.path).inserted {
        result.append(candidate)
      }
    }
    return result
  }

  private func authenticateAndComplete(path: String) {
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
      cancel(code: .failed)
      return
    }
    context.evaluatePolicy(
      .deviceOwnerAuthentication,
      localizedReason: "Unlock Pars to fill this password"
    ) { [weak self] success, _ in
      DispatchQueue.main.async {
        guard success else {
          self?.cancel(code: .userCanceled)
          return
        }
        self?.complete(path: path)
      }
    }
  }

  private func complete(path: String) {
    guard let state = ParsAutofillSharedState.loadState(),
      let root = state.storeRoot,
      let credential = ParsAutofillNative.resolveCredential(
        configPath: state.configPath,
        indexPath: state.indexPath,
        root: root,
        path: path,
        passphrase: ParsAutofillSharedState.loadPassphrase())
    else {
      cancel(code: .credentialIdentityNotFound)
      return
    }
    let passwordCredential = ASPasswordCredential(
      user: credential.username ?? credential.path,
      password: credential.password)
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
    cell.detailTextLabel?.text = candidate.username ?? candidate.matchValue
    cell.accessoryType = .disclosureIndicator
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    authenticateAndComplete(path: candidates[indexPath.row].path)
  }
}
