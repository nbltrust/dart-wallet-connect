import 'dart:async';
/// Wallet side of wallet connect protocol
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:isolate';

import 'package:convert/convert.dart';
import 'package:walletconnect/src/encryption.dart';

import 'protocol.dart';

typedef WalletConnectCallback(JsonRpcRequest req);

class WalletConnectClient {
  String bridge_url;
  String key;
  String version;
  String handshake_peer_id;
  String client_peer_id;
  String dapp_peer_id;
  WalletConnectCallback callback;
  StreamController<JsonRpcResponse> responsor;
  Completer disconnector;
  bool connected;

  WalletConnectClient.fromURI(String uri) {
    var reg = RegExp("^wc:([0-9a-f\-]*)@([0-9]*)\\\?bridge=(.*)&key=([0-9a-f]*)");
    var match = reg.firstMatch(uri);
    if(match == null) {
      throw "invalid uri format";
    }

    handshake_peer_id = match.group(1);
    version = match.group(2);
    bridge_url = Uri.decodeFull(
      match.group(3).replaceFirst('http', 'ws'));
    key = match.group(4);
    client_peer_id = generateRandomPeerId();
    responsor = new StreamController();
    disconnector = new Completer();
    callback = null;
    dapp_peer_id = null;
    connected = false;
  }

  int generateEpochReqId() {
    return DateTime.now().microsecondsSinceEpoch;
  }

  String generateRandomPeerId() {
    var r = Random.secure();
    List<int> randBuffer = new List();
    for(var i = 0; i < 16; i++) {
      randBuffer.add(r.nextInt(1<<8));
    }
    var s1 = hex.encode(randBuffer.sublist(0, 4));
    var s2 = hex.encode(randBuffer.sublist(4, 6));
    var s3 = hex.encode(randBuffer.sublist(6, 8));
    var s4 = hex.encode(randBuffer.sublist(8, 10));
    var s5 = hex.encode(randBuffer.sublist(10, 16));
    return '${s1}-${s2}-${s3}-${s4}-${s5}';
  }

  /// Calling disconnect will send a wc_sessionUpdate request to dapp
  void disconnect() {
    disconnector.complete();
  }

  void sendResponse(JsonRpcResponse resp) {
    responsor.add(resp);
  }

  void setCallback(WalletConnectCallback cb) {
    callback = cb;
  }

  void setDappPeerId(String id) {
    dapp_peer_id = id;
  }

  String prepareMessage(String topic, String type, {Map<String, dynamic> payload = null, bool silent = true}) {    
    var msg = {
      'topic': topic,
      'type': type,
      'silent': silent
    };

    print('prepare message ${jsonEncode(payload)}');
    if(payload == null) {
      msg['payload'] = '';
    } else {
      var enc_payload = encryptPayload(jsonEncode(payload), key);
      msg['payload'] = jsonEncode(enc_payload);
    }
    return jsonEncode(msg);
  }

  static void callback_loop(SendPort sendPort) async {
    var recvPort = new ReceivePort();
    sendPort.send(recvPort.sendPort);
  }

  run() async {
    print('begin websocket connection loop with url ${bridge_url}');
    final requestor = StreamController<JsonRpcRequest>();

    var ws = await WebSocket.connect(bridge_url);
    ws.listen((msg) async {
      try {
        connected = true;
        print(msg);
        var m = jsonDecode(msg);
        if(m['payload'] == '') {
          return;
        }

        // send back ack first
        ws.add(prepareMessage(m['topic'], 'ack'));

        var payload_raw = decryptPayload(jsonDecode(m['payload']), key);
        var payload = jsonDecode(payload_raw);
        print(payload);
        requestor.sink.add(JsonRpcRequest.fromJson(payload));
      } catch (error) {
        print(error);
      }
    },
    onError: (Object error) {print('websocket error');},
    onDone: () { print('websocket done');});

    ws.add(prepareMessage(handshake_peer_id, 'sub'));
    ws.add(prepareMessage(client_peer_id, 'sub'));
    
    Timer(Duration(seconds: 10), () {
      if(!connected) {
        disconnect();
      }
    });

    // listen to messages from bridge and forward to client layer
    requestor.stream.listen((req) async {
      if(callback == null) {
        return;
      }
      await callback(req);
    });

    // listen to messages from client layer and forward to bridge
    responsor.stream.listen((resp) {
      if(dapp_peer_id == null) {
        throw "can not send message before set dapp peer id";
      }
      ws.add(prepareMessage(dapp_peer_id, 'pub', payload: resp.toJson()));
    });

    disconnector.future.then((_) async {
      if(dapp_peer_id != null) {
        var request = JsonRpcRequest(
          generateEpochReqId(),
          '2.0',
          'wc_sessionUpdate',
          [WCSessionUpdateRequest(false, null, null)]
        );
        ws.add(prepareMessage(dapp_peer_id, 'pub', payload: request.toJson()));
      }
      await ws.close();
    });
  }
}