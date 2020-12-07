import 'dart:convert';
import 'package:walletconnect/walletconnect.dart';

void main() {
  String key_str = '1cabb64625342ec1a6bfa3e0473d3accfa240e9033dd2be1a0f604dc0dc9edf6';
  var payload_raw = '{"data":"8157689d43c8b921952041241686fb40120a2a6bf6e32dfdf407d9b4786e8b8bba7855f26ee3855e0bbbc092fbedb5cb5a91896bf57559c42a2d2ed3b21116bdb01b8abb6a38c109a3e7e2bb57ccde0eabf3a50775cd57564b73a09efe2f410bfd68be466f4479e937bd796823f304da83bc4b2f66761f893ca6dd441a4e8c721d8a1086e2e3c9ceacd4091a9aa2ef1c70e452af3b60cb86333de2fd7e0972de1269bc4d742400da29895f4ad4e909c0f7582f5bcf917b235b28ce05c75ea2f48c6b96697e6a879b45510caed558d3fb718562f6f5d0fbb66f60dfae013b5ccd1dd1df650d14fae2bc349968ecca2bf35a704567722be2e28e2c0cf795fb05f6a48ac002f2e9a10f7f803956c0640175ca9082420c807ed8d7bed7c9b57aeb7f919affd99b7fac55d93d340ece0f72086563fc7ddfbe6a0d616837ac519920da","hmac":"e045880f10324562feaf42aa91271297cdba149fc83524a24d5bbe3a014298a2","iv":"1fc19ffcd793c417107c66c993b41a86"}';

  var payload = jsonDecode(payload_raw);
  print(decryptPayload(payload, key_str));

  var data = 'abcdef';
  var new_payload = encryptPayload(data, key_str);
  print(new_payload);

  print(decryptPayload(new_payload, key_str));
}
