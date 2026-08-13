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
  String get managedStoreMergeLabel => '增量覆盖';

  @override
  String get managedStoreMergeDescription => '覆盖同名文件，并保留仅存在于当前副本中的文件。';

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
  String get pgpKeyDeletePartial => '受保护的私钥已删除，但公钥列表记录清理失败。';

  @override
  String keyDeleteFailed(String error) {
    return '密钥删除失败：$error';
  }

  @override
  String get delete => '删除';

  @override
  String get cancel => '取消';
}
