import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:bson/bson.dart';

class ArknightsCrypto {
  // Arknights static token: "UITpAi82pHAWwnzqHRMCwPonJLIB3WCl"
  static final Uint8List _tokenBytes = utf8.encode("UITpAi82pHAWwnzqHRMCwPonJLIB3WCl");

  // The first 16 bytes act as the AES Key, the last 16 bytes act as the mask for IV generation
  static final Uint8List _aesKey = _tokenBytes.sublist(0, 16);
  static final Uint8List _aesMask = _tokenBytes.sublist(16, 32);

  /// Decrypts files encrypted with Arknights' custom AES-CBC implementation (Cryptic A).
  static Uint8List decryptCrypticA(Uint8List data, {bool hasRsaSign = true}) {
    // Skip the 128-byte RSA signature if present
    if (hasRsaSign) {
      if (data.length <= 128) return data;
      data = data.sublist(128);
    }

    if (data.length <= 16) return data;

    // Generate the IV by XORing the first 16 bytes of the payload with the AES mask
    final ivBytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      ivBytes[i] = data[i] ^ _aesMask[i];
    }

    // The actual encrypted payload follows the 16-byte IV seed
    final encryptedPayload = data.sublist(16);
    final key = Key(_aesKey);
    final iv = IV(ivBytes);

    // Decrypt using AES-CBC with PKCS7 padding (padding removal is handled automatically)
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));
    final decrypted = encrypter.decryptBytes(Encrypted(encryptedPayload), iv: iv);

    return Uint8List.fromList(decrypted);
  }

  /// Determines if the data is BSON or JSON and parses it into a standard Map.
  static dynamic parseJsonOrBson(Uint8List data) {
    // Heuristic: If there is a null byte (\x00) in the first 256 bytes, it's very likely BSON
    final checkLength = data.length < 256 ? data.length : 256;
    bool isBson = data.sublist(0, checkLength).contains(0);

    if (isBson) {
      try {
        return BsonCodec.deserialize(BsonBinary.from(data));
      } catch (e) {
        // Fallback to JSON if BSON parsing fails (false positive)
        return jsonDecode(utf8.decode(data));
      }
    } else {
      return jsonDecode(utf8.decode(data));
    }
  }
}
