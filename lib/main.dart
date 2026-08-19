import 'package:flutter/material.dart';
import 'package:relaygo/app.dart';
import 'package:relaygo/config/constants.dart';
import 'package:relaygo/database/database_helper.dart';
import 'package:relaygo/utils/encryption.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DatabaseHelper.init();

  // 主密钥：首次运行生成并持久化到 vault 盒
  final vault = DatabaseHelper.vault;
  String masterKey;
  if (vault.containsKey(Constants.masterKeyName)) {
    masterKey = vault.get(Constants.masterKeyName) as String;
  } else {
    masterKey = EncryptionUtil.generateMasterKeyBase64();
    await vault.put(Constants.masterKeyName, masterKey);
  }
  EncryptionUtil.init(masterKey);

  runApp(const MyApp());
}
