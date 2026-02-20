import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';

class SecureVault {
  static const String _internalSalt = "SKYSYS_PRO_SALT_99821_Bokachondro985";

  /// Manual PBKDF2-HMAC-SHA256 implementation
  static Uint8List _pbkdf2(
      Uint8List password, Uint8List salt, int iterations, int keyLength) {
    final hmac = Hmac(sha256, password);
    final blockCount = (keyLength / 32).ceil(); // SHA-256 = 32 bytes
    final result = <int>[];

    for (int i = 1; i <= blockCount; i++) {
      // U1 = HMAC(password, salt + INT(i))
      final saltWithIndex = Uint8List(salt.length + 4);
      saltWithIndex.setAll(0, salt);
      saltWithIndex[salt.length]     = (i >> 24) & 0xff;
      saltWithIndex[salt.length + 1] = (i >> 16) & 0xff;
      saltWithIndex[salt.length + 2] = (i >> 8)  & 0xff;
      saltWithIndex[salt.length + 3] =  i        & 0xff;

      var u = Uint8List.fromList(hmac.convert(saltWithIndex).bytes);
      final block = Uint8List.fromList(u);

      for (int j = 1; j < iterations; j++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (int k = 0; k < block.length; k++) {
          block[k] ^= u[k];
        }
      }
      result.addAll(block);
    }

    return Uint8List.fromList(result.sublist(0, keyLength));
  }

  static encrypt.Key _deriveKey(String password) {
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    final saltBytes = Uint8List.fromList(utf8.encode(_internalSalt));
    final derivedKey = _pbkdf2(passwordBytes, saltBytes, 2000, 32);
    return encrypt.Key(derivedKey);
  }

  /// Encrypts String -> Base64(IV + EncryptedData)
  static String pack(String plainText, String password) {
    final key = _deriveKey(password);
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.gcm));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    final combined = "${iv.base64}:${encrypted.base64}";
    return base64.encode(utf8.encode(combined));
  }

  /// Decrypts Base64 -> Original String
  static String unpack(String packedData, String password) {
    try {
      final decodedCombined = utf8.decode(base64.decode(packedData));
      final parts = decodedCombined.split(':');
      if (parts.length != 2) return "ERROR: Invalid file format";

      final iv = encrypt.IV.fromBase64(parts[0]);
      final cipherText = parts[1];
      final key = _deriveKey(password);
      final encrypter = encrypt.Encrypter(
          encrypt.AES(key, mode: encrypt.AESMode.gcm));
      return encrypter.decrypt64(cipherText, iv: iv);
    } catch (e) {
      return "ERROR: Decryption failed (Wrong password or corrupted file)";
    }
  }
}