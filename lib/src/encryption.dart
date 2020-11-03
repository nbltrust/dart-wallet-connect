import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' show Key, AES, AESMode, Encrypted, IV;

String decryptPayload(Map<String, dynamic> encrypedPayload, String keyHex) {
  var data = hex.decode(encrypedPayload['data']);
  var iv = hex.decode(encrypedPayload['iv']);
  var key = hex.decode(keyHex);
  var hmacSha256 = new Hmac(sha256, key);
  var digest = hmacSha256.convert(data + iv);
  if(hex.encode(digest.bytes) != encrypedPayload['hmac']) {
    throw "hmac check failed";
  }

  var aes = AES(Key(key), mode: AESMode.cbc, padding: 'PKCS7');
  return String.fromCharCodes(aes.decrypt(Encrypted(data), iv: IV(iv)));
}

Map<String, String> encryptPayload(String content, String keyHex) {
  var key = hex.decode(keyHex);
  var iv = IV.fromSecureRandom(16);
  var hmacSha256 = new Hmac(sha256, key);
  

  var aes = AES(Key(key), mode: AESMode.cbc, padding: 'PKCS7');
  var encrypted = aes.encrypt(Uint8List.fromList(content.codeUnits), iv: iv);
  var digest = hmacSha256.convert(encrypted.bytes + iv.bytes);
  return {
    'data': encrypted.base16,
    'iv': iv.base16,
    'hmac': hex.encode(digest.bytes)
  };
}
