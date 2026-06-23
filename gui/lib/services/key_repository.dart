import '../models/key_record.dart';

abstract interface class KeyRepository {
  List<KeyRecord> get keys;
}
