import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';

class SecureVault {
  // A unique salt makes the key unique even if two people use the same password
  static const String _internalSalt = "SKYSYS_PRO_SALT_99821_Bokachondro985"; 

  /// Derives a 256-bit key using SHA-256 stretching
  static encrypt.Key _deriveKey(String password) {
    // We combine the password and salt, then hash it to create a 32-byte (256-bit) key
    // This is a simplified version of key stretching suitable for the 'crypto' package
    var bytes = utf8.encode(password + _internalSalt);
    var digest = sha256.convert(bytes);
    return encrypt.Key(Uint8List.fromList(digest.bytes));
  }

  /// Encrypts String -> Base64(IV + EncryptedData)
  static String pack(String plainText, String password) {
    final key = _deriveKey(password);
    final iv = encrypt.IV.fromSecureRandom(16); // Random IV for every file
    
    // Note: Standard AES in 'encrypt' package usually uses PKCS7 padding
    // Using SIC/CTR or CBC mode is often more stable across Flutter versions than GCM 
    // unless you specifically need authentication tags.
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final encrypted = encrypter.encrypt(plainText, iv: iv);

    // Combine IV and Data with a separator
    String combined = "${iv.base64}:${encrypted.base64}";
    
    // Final result is Base64 encoded
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
      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
      
      return encrypter.decrypt64(cipherText, iv: iv);
    } catch (e) {
      return "ERROR: Decryption failed (Wrong password or corrupted file)";
    }
  }
}
