import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';

class SecureVault {
  // A unique salt makes the key unique even if two people use the same password
  static const String _internalSalt = "SKYSYS_PRO_SALT_99821"; 

  /// Derives a 256-bit key using PBKDF2
  static encrypt.Key _deriveKey(String password) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256,
      iterations: 2000, // Makes brute force 2000x slower
      bits: 256,
    );
    
    // Correctly convert strings to Uint8List for the crypto library
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    final saltBytes = Uint8List.fromList(utf8.encode(_internalSalt));

    final bytes = pbkdf2.deriveSync(passwordBytes, saltBytes);
    return encrypt.Key(bytes);
  }

  /// Encrypts String -> Base64(IV + EncryptedData)
  static String pack(String plainText, String password) {
    final key = _deriveKey(password);
    final iv = encrypt.IV.fromSecureRandom(16); // Random IV for every file
    
    // Using AES-GCM for Authenticated Encryption
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
    final encrypted = encrypter.encrypt(plainText, iv: iv);

    // Combine IV and Data with a separator for easy extraction
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
      final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
      
      return encrypter.decrypt64(cipherText, iv: iv);
    } catch (e) {
      return "ERROR: Decryption failed (Wrong password or corrupted file)";
    }
  }
}