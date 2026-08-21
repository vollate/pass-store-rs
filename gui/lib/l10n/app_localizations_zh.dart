// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get managedStoreConflictTitle => '同名仓库已存在';

  @override
  String managedStoreConflictDescription(String storeName) {
    return 'App 内已存在名为 $storeName 的托管副本。请选择本次导入方式。';
  }

  @override
  String get managedStoreReplaceLabel => '彻底覆盖';

  @override
  String get managedStoreReplaceDescription => '以所选目录完整替换现有副本，并删除所选目录中不存在的旧文件。';

  @override
  String get noPasswordStoreConfigured => '尚未配置密码仓库。';

  @override
  String get passwordStoreFolderNotFound => '找不到密码仓库目录。';

  @override
  String get chooseFolderAndImport => '选择目录并导入';

  @override
  String get copyIntoAppStorage => '复制到 App 存储';

  @override
  String get copyIntoAppStorageDescription =>
      'Pars 会将所选密码仓库复制到 App 存储，以确保所有文件均可访问。';

  @override
  String get storeAvailable => '可用';

  @override
  String get storeFolderNotFound => '找不到目录';

  @override
  String get deleteAppCopy => '删除 App 副本';

  @override
  String passwordStoreKeyReference(String storeNames) {
    return '由 $storeNames 的 .gpg-id 引用';
  }

  @override
  String get localKeyMaterialMissing => '本机尚未导入对应密钥材料';

  @override
  String get privateKeyMaterial => '私钥';

  @override
  String get publicKeyMaterial => '公钥';

  @override
  String get storeActionInProgress => '正在处理…';

  @override
  String get storeImportCancelled => '未选择任何目录。';

  @override
  String get storeImportNoPasswords => '未找到任何密码。';

  @override
  String storeImportSucceeded(int passwordCount) {
    return '导入完成：共 $passwordCount 个密码。';
  }

  @override
  String get pgpPreparationInProgress => '正在保护私钥…';

  @override
  String get pgpPassphraseRequired => '该私钥需要密码。';

  @override
  String get pgpPassphraseIncorrect => '该密码无法解锁私钥，请重试。';

  @override
  String get pgpUnsupportedProtection => '该私钥使用了不支持的保护格式。';

  @override
  String get pgpReprotectionFailed => '无法安全地转换并保护本地私钥。';

  @override
  String get deleteKeyAction => '删除密钥';

  @override
  String deleteKeyTitle(String keyType) {
    return '删除 $keyType 密钥';
  }

  @override
  String fingerprintValue(String fingerprint) {
    return '指纹：$fingerprint';
  }

  @override
  String deleteKeyDescription(String confirmation) {
    return '这将从本设备永久删除本地密钥材料，包括受密码保护的私钥。输入 $confirmation 以确认删除。';
  }

  @override
  String deleteKeyConfirmation(String confirmation) {
    return '输入 $confirmation 以确认';
  }

  @override
  String keyDeleted(String keyName) {
    return '已删除 $keyName';
  }

  @override
  String keyDeleteFailed(String error) {
    return '密钥删除失败：$error';
  }

  @override
  String get delete => '删除';

  @override
  String get cancel => '取消';

  @override
  String get settingsTitle => '设置';

  @override
  String get appearanceSection => '外观';

  @override
  String get languageTitle => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageEnglish => '英语';

  @override
  String get languageChinese => '中文';

  @override
  String get languageUnavailable => '语言选择当前不可用。';

  @override
  String get languageSaveFailed => '无法保存语言偏好。';

  @override
  String get vaultTitle => '密码库';

  @override
  String get manageTitle => '管理';

  @override
  String get retry => '重试';

  @override
  String get copy => '复制';

  @override
  String get close => '关闭';

  @override
  String get continueAction => '继续';

  @override
  String get save => '保存';

  @override
  String get clear => '清除';

  @override
  String get setup => '设置';

  @override
  String get status => '状态';

  @override
  String get create => '创建';

  @override
  String get createPassword => '创建密码';

  @override
  String selectedCount(int count) {
    return '已选择 $count 项';
  }

  @override
  String get importAction => '导入';

  @override
  String get exportAction => '导出';

  @override
  String get edit => '编辑';

  @override
  String get move => '移动';

  @override
  String get rename => '重命名';

  @override
  String get regenerate => '重新生成';

  @override
  String get select => '选择';

  @override
  String get back => '返回';

  @override
  String get details => '详情';

  @override
  String get moreActions => '更多操作';

  @override
  String get searchVaultHint => '按名称或路径搜索';

  @override
  String get recentSection => '最近使用';

  @override
  String get favoritesSection => '收藏';

  @override
  String get searchResultsSection => '搜索结果';

  @override
  String get browseSection => '浏览';

  @override
  String browsePathSection(String path) {
    return '浏览：$path';
  }

  @override
  String get noRecentEntries => '暂无最近使用的条目。';

  @override
  String get noFavoriteEntries => '暂无收藏条目。';

  @override
  String get noSearchResults => '没有符合搜索条件的条目。';

  @override
  String get noStoreEntries => '此密码库中暂无条目。';

  @override
  String get noFolderEntries => '此文件夹中暂无条目。';

  @override
  String get upOneLevel => '上一级';

  @override
  String get couldNotLoadVault => '无法加载密码库。';

  @override
  String get gitClean => '已同步';

  @override
  String get gitNeedPull => '需要拉取';

  @override
  String get gitUncommitted => '有未提交更改';

  @override
  String get gitSyncFailed => '同步失败';

  @override
  String copiedEntryPassword(String entryName) {
    return '已复制 $entryName 的密码';
  }

  @override
  String get couldNotCopyPassword => '无法复制密码。';

  @override
  String get favoriteUpdateFailed => '无法更新收藏状态。';

  @override
  String entryCount(int count) {
    return '$count 个条目';
  }

  @override
  String get pgpPassphraseRequiredTitle => '需要 PGP 密码';

  @override
  String get pgpPassphraseLabel => 'PGP 密码';

  @override
  String get unlockEntry => '解锁条目';

  @override
  String get decryptEntryFailedTitle => '无法解密条目';

  @override
  String get copyPassword => '复制密码';

  @override
  String get reveal => '显示';

  @override
  String get hide => '隐藏';

  @override
  String get favorite => '收藏';

  @override
  String get unfavorite => '取消收藏';

  @override
  String get openUrl => '打开网址';

  @override
  String get qrCode => '二维码';

  @override
  String get fields => '字段';

  @override
  String get rawNotes => '原始备注';

  @override
  String get passwordQrCode => '密码二维码';

  @override
  String get closeQrCode => '关闭密码二维码';

  @override
  String copiedField(String fieldLabel) {
    return '已复制$fieldLabel';
  }

  @override
  String get couldNotOpenUrl => '无法打开网址。';

  @override
  String get manageSubtitle => '批量或逐项维护密码。';

  @override
  String get generateAndSave => '生成并保存';

  @override
  String get generateAndSaveDescription => '创建一个或多个随机密码条目。';

  @override
  String get saveExistingPassword => '保存已有密码';

  @override
  String get saveExistingPasswordDescription => '手动保存已有凭据。';

  @override
  String get batchDelete => '批量删除';

  @override
  String get batchDeleteDescription => '预览完整路径后删除所选条目。';

  @override
  String get regenerateSelected => '重新生成所选密码';

  @override
  String get regenerateSelectedDescription => '替换密码行并保留字段和备注。';

  @override
  String get editEntries => '编辑条目';

  @override
  String get editEntriesDescription => '在不更改路径的情况下更新密码和备注。';

  @override
  String get moveEntry => '移动条目';

  @override
  String get moveEntryDescription => '将一个条目移动到其他文件夹。';

  @override
  String get renameEntry => '重命名条目';

  @override
  String get renameEntryDescription => '更改条目路径并处理覆盖冲突。';

  @override
  String get deleteEntry => '删除条目';

  @override
  String get deleteEntryDescription => '确认名称后删除一个条目。';

  @override
  String get noEntriesToManage => '没有可管理的条目。';

  @override
  String get selectAtLeastOneEntry => '请至少选择一个条目。';

  @override
  String get manageUnavailable => '管理操作当前不可用。';

  @override
  String get batchMove => '批量移动';

  @override
  String get batchRename => '批量重命名';

  @override
  String get destinationFolder => '目标文件夹';

  @override
  String get entryPath => '条目路径';

  @override
  String get newEntryPath => '新条目路径';

  @override
  String get prefix => '前缀';

  @override
  String get suffix => '后缀';

  @override
  String get overwriteTarget => '目标存在时覆盖';

  @override
  String get overwriteEntry => '条目存在时覆盖';

  @override
  String get moveSelected => '移动所选条目';

  @override
  String get renameSelected => '重命名所选条目';

  @override
  String get deleteSelected => '删除所选条目';

  @override
  String get regenerateBatch => '批量重新生成';

  @override
  String get noEntriesAvailable => '没有可用条目';

  @override
  String get noEntriesToEdit => '没有可编辑的条目。';

  @override
  String get noSymbols => '不使用符号';

  @override
  String get confirmation => '确认文字';

  @override
  String get password => '密码';

  @override
  String get commitAfterOperation => '操作后提交 Git';

  @override
  String get saveGeneratedPassword => '保存生成的密码';

  @override
  String get savePassword => '保存密码';

  @override
  String get saveEditedEntry => '保存编辑';

  @override
  String get replaceFirstLine => '替换第一行';

  @override
  String get selectedPathPrefix => '已选择';

  @override
  String get defaultPathPrefix => '默认';

  @override
  String get changeAction => '更改';

  @override
  String get chooseAction => '选择';

  @override
  String get noKeyRepository => '没有可用的密钥仓库';

  @override
  String get noSshRepository => '没有可用的 SSH 仓库';

  @override
  String get enterPassphrase => '请输入密码。';

  @override
  String get selectPrivatePgpKey => '请选择或导入私有 PGP 密钥。';

  @override
  String get storeFolder => '密码库文件夹';

  @override
  String get remoteUrlField => '远程仓库 URL';

  @override
  String get commitMessageField => '提交信息';

  @override
  String get remoteNameField => '远程仓库名称';

  @override
  String get gitOperationsUnavailable => 'Git 操作当前不可用。';

  @override
  String get gitArgumentRequired => '请至少输入一个 Git 参数。';

  @override
  String get never => '永不';

  @override
  String minutesShort(int count) {
    return '$count 分钟';
  }

  @override
  String hoursShort(int count) {
    return '$count 小时';
  }

  @override
  String get immediately => '立即';

  @override
  String get untilAppExit => '直到应用退出';

  @override
  String importedKey(String keyName) {
    return '已导入 $keyName';
  }

  @override
  String importedKeyRememberFailed(String keyName) {
    return '已导入 $keyName，但记住密码失败。';
  }

  @override
  String get deleteLocalStore => '删除本地密码库';

  @override
  String pathValue(String path) {
    return '路径：$path';
  }

  @override
  String typeToConfirm(String value) {
    return '输入 $value 以确认';
  }

  @override
  String get entryField => '条目';

  @override
  String get batchSelection => '批量选择';

  @override
  String get securitySection => '安全';

  @override
  String get securityPrivacySection => '安全与隐私';

  @override
  String get vaultSyncSection => '密码库与同步';

  @override
  String get autofillSection => '自动填充';

  @override
  String get advancedSupportSection => '高级与支持';

  @override
  String get platformSection => '平台';

  @override
  String get gestureBiometricsTitle => '手势锁与生物识别';

  @override
  String get lockOnResumeState => '返回应用时锁定';

  @override
  String get gestureConfiguredState => '手势解锁已配置';

  @override
  String get pgpSessionTimeoutTitle => 'PGP 会话超时';

  @override
  String get keychainPassphraseTitle => 'KMS / 钥匙串密码';

  @override
  String get pgpPassphraseCachedState => 'PGP 密码已缓存';

  @override
  String get optionalPassphraseCacheState => '可选的加密密码缓存';

  @override
  String get sshKeysTitle => 'SSH 密钥';

  @override
  String get githubAccessKeysDescription => 'GitHub 访问密钥';

  @override
  String get gitSyncTitle => 'Git 同步与远程仓库';

  @override
  String get gitSyncDescription => '拉取、推送、状态、远程仓库';

  @override
  String get advancedGitArgsTitle => '高级 Git 参数';

  @override
  String get advancedGitArgsDescription => '仅填写 git 之后的参数';

  @override
  String get systemAutofillTitle => '系统自动填充';

  @override
  String get runtimeDiagnosticsTitle => '运行时诊断';

  @override
  String get runtimeDiagnosticsDescription => '桥接、核心、加密、Git、密钥存储';

  @override
  String get bridgeLoadedLabel => '桥接已加载';

  @override
  String get coreVersionLabel => '核心版本';

  @override
  String get nativeLibraryLabel => '原生库';

  @override
  String get pgpBackendLabel => 'PGP 后端';

  @override
  String get gitBackendLabel => 'Git 后端';

  @override
  String get keyStorageBackendLabel => '密钥存储后端';

  @override
  String get yes => '是';

  @override
  String get no => '否';

  @override
  String get replaceCachedPassphrase => '替换缓存密码';

  @override
  String get noCachedPassphrase => '当前未缓存 PGP 密码。';

  @override
  String cachedForKey(String keyName) {
    return '缓存密钥：$keyName';
  }

  @override
  String get updatePasswordStore => '更新密码库';

  @override
  String get featureUnavailableDescription => '当前仓库不提供此功能所需的操作。请使用桥接仓库以启用此功能。';

  @override
  String get changeGesture => '更改手势';

  @override
  String get requireUnlockOnResume => '返回应用时要求解锁';

  @override
  String get gestureFallbackDescription => '手势解锁将作为备用方式';

  @override
  String get biometricUnlock => '生物识别解锁';

  @override
  String get enabledOnDevice => '已在此设备启用';

  @override
  String get availableOnDevice => '此设备支持';

  @override
  String get unavailableOnDevice => '此设备不支持';

  @override
  String get gestureLock => '手势锁';

  @override
  String get passwordStore => '密码库';

  @override
  String get pgpKey => 'PGP 密钥';

  @override
  String get sshKey => 'SSH 密钥';

  @override
  String get autoLockTimeout => '自动锁定时间';

  @override
  String get resetOnboarding => '重置引导';

  @override
  String get drawConfirmGesture => '绘制并确认新的本地解锁手势。';

  @override
  String get storePgpPassphrase => '保存 PGP 密码';

  @override
  String get savedInSecureStorage => '已保存到平台安全存储';

  @override
  String get noPrivatePgpKeys => '没有私有 PGP 密钥';

  @override
  String get createPrivatePgpKeyFirst => '保存密码前请先导入或创建私有 PGP 密钥。';

  @override
  String get rebuildPaths => '重建路径索引';

  @override
  String get readUrlFields => '读取 URL 字段';

  @override
  String get clearUrlAliases => '清除 URL 别名';

  @override
  String get clearAll => '全部清除';

  @override
  String get readEncryptedUrlFieldsTitle => '读取加密 URL 字段？';

  @override
  String readEncryptedUrlFieldsDescription(int count) {
    return '此可选操作会解密所选的 $count 个条目一次，并且只保存规范化的网站别名。基于路径的自动填充不需要此操作。';
  }

  @override
  String get readSelectedEntries => '读取所选条目';

  @override
  String get autofillRebuiltSuccess => '已基于路径重建自动填充数据，未解密任何条目。';

  @override
  String get autofillAliasesCleared => '已清除加密网站别名。';

  @override
  String get autofillDataCleared => '已清除自动填充数据。';

  @override
  String get clearAutofillConfirmation => '移除此密码库的全部共享自动填充候选项？这不会删除密码条目。';

  @override
  String get openSystemPasswordSettings => '请打开系统密码设置。';

  @override
  String get autofillAliasesUpdated => '已更新加密网站别名。';

  @override
  String get noEntriesToEnrich => '没有可用于补充网站信息的密码条目。';

  @override
  String get autofillBridgeUnavailable => '自动填充桥接不可用';

  @override
  String get autofillNotRefreshed => '尚未刷新';

  @override
  String get autofillReady => '可用';

  @override
  String get autofillNeedsRebuild => '需要重建';

  @override
  String get autofillBusy => '正在处理…';

  @override
  String get autofillDisabled => '已停用';

  @override
  String get autofillUnavailableState => '不可用';

  @override
  String autofillIndexedEntries(int count) {
    return '已索引 $count 个条目';
  }

  @override
  String get unavailable => '不可用';

  @override
  String get createOrImportKey => '创建或导入密钥。';

  @override
  String get noPgpKeys => '没有 PGP 密钥';

  @override
  String get noSshKeys => '没有 SSH 密钥';

  @override
  String keyActionsTooltip(String keyType, String keyName) {
    return '$keyType 密钥 $keyName 的操作';
  }

  @override
  String get exportPublic => '导出公钥';

  @override
  String get exportPrivate => '导出私钥';

  @override
  String get addToGpgId => '添加到 .gpg-id';

  @override
  String get importPgpKey => '导入 PGP 密钥';

  @override
  String get importSshKey => '导入 SSH 密钥';

  @override
  String get textSource => '文本';

  @override
  String get fileSource => '文件';

  @override
  String get importSshKeyFile => '导入 SSH 密钥文件';

  @override
  String get nameField => '名称';

  @override
  String get keyTextField => '密钥文本';

  @override
  String get keyFileField => '密钥文件';

  @override
  String get pastePgpKeyHelp => '粘贴 PGP 公钥或私钥。';

  @override
  String get pgpPassphraseUnlockHelp => '解锁此私钥时需要输入。';

  @override
  String get unlockAndImport => '解锁并导入';

  @override
  String get exportPrivateKey => '导出私钥';

  @override
  String privateExportSensitive(String confirmation) {
    return '导出私钥属于敏感操作。输入 $confirmation 以导出。';
  }

  @override
  String get exportedKey => '已导出的密钥';

  @override
  String get createImportCloneStore => '创建、导入或克隆密码库。';

  @override
  String get removeFromApp => '从应用中移除';

  @override
  String get cloneAction => '克隆';

  @override
  String get pull => '拉取';

  @override
  String get push => '推送';

  @override
  String get recoverPull => '恢复拉取';

  @override
  String get pushAfterCommit => '提交后推送';

  @override
  String get commit => '提交';

  @override
  String get listRemotes => '列出远程仓库';

  @override
  String get addRemote => '添加远程仓库';

  @override
  String get updateRemote => '更新远程仓库';

  @override
  String get removeRemote => '移除远程仓库';

  @override
  String get deleteLocalRepo => '删除本地仓库';

  @override
  String get gitArgsOnlyDescription => '仅输入 git 之后的参数，不支持 Shell 语法。';

  @override
  String get runSelectedCommand => '运行所选命令';

  @override
  String exitCodeValue(String value) {
    return '退出码：$value';
  }

  @override
  String get standardOutput => '标准输出';

  @override
  String get standardError => '标准错误';

  @override
  String get success => '成功';

  @override
  String get failed => '失败';

  @override
  String get operationFailed => '操作失败，请重试或打开详情。';

  @override
  String get actionSaved => '已保存';

  @override
  String get actionEdited => '已编辑';

  @override
  String get actionDeleted => '已删除';

  @override
  String get actionMoved => '已移动';

  @override
  String get actionRenamed => '已重命名';

  @override
  String get actionRegenerated => '已重新生成';

  @override
  String get actionUpdated => '已更新';

  @override
  String get entryOverwroteExisting => '（已覆盖现有条目）';

  @override
  String get entryCommitted => '并已提交';

  @override
  String entryOperationSummary(
    String action,
    String path,
    String overwrite,
    String commit,
  ) {
    return '$action：$path$overwrite$commit';
  }

  @override
  String batchOperationSummary(String action, int count, String commit) {
    return '$action $count 个条目$commit';
  }

  @override
  String batchFailureSuffix(int count) {
    return '；$count 个失败';
  }

  @override
  String postMutationCommitFailed(String mutationSummary) {
    return '$mutationSummary，但可选的 Git 提交失败。密码库修改未回滚。';
  }

  @override
  String get diagnosticDetails => '诊断详情';

  @override
  String get lockNow => '立即锁定';

  @override
  String get unlockPars => '解锁 Pars';

  @override
  String get drawGestureToUnlock => '绘制手势以打开本地应用会话。';

  @override
  String get unlockWithBiometrics => '使用生物识别解锁';

  @override
  String get gestureDidNotMatch => '手势不匹配';

  @override
  String get biometricUnlockFailed => '生物识别解锁失败';

  @override
  String get resetGesture => '重置手势';

  @override
  String get drawSameGesture => '请再次绘制相同手势。';

  @override
  String get drawAtLeastFourDots => '请至少连接 4 个点。';

  @override
  String get startNewGesture => '请重新绘制一个新手势。';

  @override
  String get useAtLeastFourDots => '请至少使用 4 个点。';

  @override
  String get gestureCapturedConfirm => '手势已记录，请再确认一次。';

  @override
  String get gesturesDidNotMatch => '两次手势不一致，请重新开始。';

  @override
  String get gestureConfirmed => '手势已确认。';

  @override
  String get gesturePatternInput => '手势图案输入';

  @override
  String gestureDot(int number) {
    return '手势点 $number';
  }

  @override
  String get clearGesture => '清除手势';

  @override
  String get submitGesture => '提交手势';

  @override
  String get rememberInKeychain => '记住到钥匙串/KMS';

  @override
  String get rememberPassphraseDescription =>
      '默认关闭。除非你明确选择记住，否则密码仅在本次会话中保留在内存。';

  @override
  String get inspectingKeyMaterial => '正在检查密钥材料…';

  @override
  String get setGestureLock => '设置手势锁';

  @override
  String get enableBiometricUnlock => '启用生物识别解锁';

  @override
  String get choosePgpKey => '选择 PGP 密钥';

  @override
  String get setupSshGithub => '为 GitHub 设置 SSH';

  @override
  String get setupPasswordStore => '设置密码库';

  @override
  String get reviewSetup => '检查设置';

  @override
  String get gestureStepSubtitle => '使用九宫格手势作为 Pars 的本地解锁方式。';

  @override
  String get biometricsStepSubtitle => '生物识别为可选项，手势仍作为备用方式。';

  @override
  String get pgpStepSubtitle => '选择、创建或导入用于加密密码的密钥。';

  @override
  String get sshStepSubtitle => 'SSH 为可选项，可用于经过认证的 Git 操作。';

  @override
  String get storeStepSubtitle => '选择 Pars 打开或创建密码库的方式。';

  @override
  String get reviewStepSubtitle => '打开密码库前确认必需设置。';

  @override
  String get githubSshSettings => 'GitHub SSH 设置';

  @override
  String onboardingProgress(int current, int total) {
    return '第 $current 步，共 $total 步';
  }

  @override
  String get optional => '可选';

  @override
  String get gestureStep => '手势';

  @override
  String get biometricsStep => '生物识别';

  @override
  String get pgpStep => 'PGP';

  @override
  String get sshStep => 'SSH';

  @override
  String get storeStep => '密码库';

  @override
  String get reviewStep => '检查';

  @override
  String get skipBiometrics => '跳过生物识别';

  @override
  String get finishSetup => '完成设置';

  @override
  String get noPgpKeysFound => '未找到 PGP 密钥';

  @override
  String get createOrImportEncryptionKey => '创建或导入用于加密条目的密钥。';

  @override
  String get usePgpKey => '使用 PGP 密钥';

  @override
  String get createPgpKey => '创建 PGP 密钥';

  @override
  String get createSshKey => '创建 SSH 密钥';

  @override
  String get emailField => '电子邮箱';

  @override
  String get passphraseField => '密码';

  @override
  String get noSshKeysConfigured => '尚未配置 SSH 密钥';

  @override
  String get sshOptionalDescription => 'SSH 为可选项，稍后仍可添加。';

  @override
  String get generateSshKey => '生成 SSH 密钥';

  @override
  String get githubSettings => 'GitHub 设置';

  @override
  String get skipSsh => '跳过 SSH';

  @override
  String get createLocalStore => '创建本地密码库';

  @override
  String get importLocalStore => '导入本地密码库';

  @override
  String get cloneGitStore => '克隆 Git 密码库';

  @override
  String get addSshBeforeClone => '克隆 Git 密码库前请先添加 SSH 密钥。';

  @override
  String get noStoreRepository => '没有可用的密码库仓库';

  @override
  String get configured => '已配置';

  @override
  String get required => '必需';

  @override
  String get enabled => '已启用';

  @override
  String get skipped => '已跳过';

  @override
  String get notFound => '未找到';

  @override
  String get gitMetadataNotFoundTitle => '未找到 Git 元数据';

  @override
  String get gitMetadataNotFoundMessage =>
      '该文件夹可能仅供本地使用，也可能是 Android 隐藏了 .git 数据。初始化会创建全新历史，无法恢复原有历史。';

  @override
  String get initializeGit => '初始化 Git';

  @override
  String get continueWithoutGit => '不使用 Git 继续';

  @override
  String keyCount(int count) {
    return '$count 个密钥';
  }

  @override
  String get storeFirstSetupSubtitle => '导入或克隆现有密码库；仅在没有密码库时创建新库。';

  @override
  String get createStoreRecipientSubtitle => '只为即将创建的新密码库选择私有 PGP 密钥。';

  @override
  String get contextualRepairSubtitle => '仅修复当前密码库明确需要的项目。';

  @override
  String get repairPasswordStore => '修复密码库';

  @override
  String get createStoreNeedsPgpKey => '创建新密码库前，需要先选择或导入私有 PGP 密钥。';

  @override
  String get gitOptionalForLocalStore => 'Git 为可选项；不启用 Git 也能正常使用密码库。';

  @override
  String get sshKeyRequiredForRemote => '此远端需要 SSH 密钥';

  @override
  String get sshRequiredForThisClone => '该 SSH 远端需要密钥；HTTPS 克隆不需要。';

  @override
  String get missingGpgIdTitle => '缺少加密接收者';

  @override
  String get missingGpgIdMessage =>
      '请选择私有 PGP 密钥来创建缺失的 .gpg-id；此处绝不会替换已有接收者文件。';

  @override
  String get requiredPgpKeyMissingTitle => '缺少所需的私有 PGP 密钥';

  @override
  String requiredPgpKeyMissingMessage(String recipients) {
    return '请导入匹配以下任一接收者的私有密钥：$recipients';
  }

  @override
  String get requiredPrivatePgpKey => '需要匹配的私有 PGP 密钥。';

  @override
  String get pgpKeyDoesNotMatchStore => '该私有密钥与密码库接收者不匹配。';

  @override
  String get invalidGitMetadataTitle => 'Git 元数据无效';

  @override
  String get invalidGitMetadataMessage => '该密码库包含不可用的 Git 元数据。请断开后重新导入或克隆有效副本。';

  @override
  String get disconnectStore => '断开密码库';

  @override
  String get gitDisabledState => '未启用 Git · 仅本地密码库';

  @override
  String get gitLocalState => '本地 Git · 无远端';

  @override
  String get gitRemoteState => '已配置 Git 远端';

  @override
  String get storeIssues => '需要修复';

  @override
  String get sshKeysGitOnlyDescription =>
      'SSH 密钥仅用于 SSH Git 远端；HTTPS 和仅本地密码库不需要。';

  @override
  String get storeRemovalInProgressTitle => '正在移除密码库…';

  @override
  String get storeRemovalInProgressDescription =>
      'Pars 正在清除本地会话和自动填充数据，然后再更改已配置的密码库。';
}
