/// ClientMeta is sent by sessionRequest message
/// 
/// Client meta structure is described at:
/// https://github.com/WalletConnect/walletconnect-docs/blob/master/tech-spec.md
class ClientMeta {
  final String url;
  final String name;
  final String description;
  final List<String> icons;

  ClientMeta.fromJson(Map<String, dynamic> json):
    url = json['url'],
    name = json['name'],
    description = json['description'],
    icons = List<String>.from(json['icons']);

  ClientMeta(this.url, this.name, this.description, this.icons);

  Map<String, dynamic> toJson() => {
    'url': url,
    'name': name,
    'description': description,
    'icons': icons
  };
}

class WCSessionRequestRequest {
  final String peerId;
  final ClientMeta peerMeta;
  final int chainId;

  WCSessionRequestRequest.fromJson(Map<String, dynamic> json):
    peerId = json['peerId'],
    peerMeta = ClientMeta.fromJson(json['peerMeta']),
    chainId = json['chainId'];

  Map<String, dynamic> toJson() => {
    'peerId': peerId,
    'peerMeta': peerMeta.toJson(),
    'chainId': chainId
  };
}


class WCSessionUpdateRequest {
  final bool approved;
  final int chainId;
  final List<String> accounts;

  WCSessionUpdateRequest(this.approved, this.chainId, this.accounts);

  WCSessionUpdateRequest.fromJson(Map<String, dynamic> json):
    approved = json['approved'],
    chainId = json['chainId'],
    accounts = json['accounts'];

  Map<String, dynamic> toJson() => {
    'approved': approved,
    'chainId': chainId,
    'accounts': accounts
  };
}

class WCSessionRequestResponse {
  final String peerId;
  final ClientMeta clientMeta;
  final bool approved;
  final int chainId;
  final List<String> accounts;

  WCSessionRequestResponse(this.peerId, this.clientMeta, this.approved, this.chainId, this.accounts);
  Map<String, dynamic> toJson() => {
    'peerId': peerId,
    'peerMeta': clientMeta.toJson(),
    'approved': approved,
    'chainId': chainId,
    'accounts': accounts,
  };
}

class ErrorResponse {
  final String message;

  ErrorResponse(this.message);

  Map<String, dynamic> toJson() => {
    'code': -1,
    'message': message
  };
}

class JsonRpcRequest {
  final int id;
  final String jsonrpc;
  final String method;
  List<dynamic> params;

  JsonRpcRequest(this.id, this.jsonrpc, this.method, this.params);
  JsonRpcRequest.fromJson(Map<String, dynamic> json):
    id = json['id'], 
    method = json['method'],
    jsonrpc = json['jsonrpc']
  {
    switch(method) {
      case "wc_sessionRequest":
        params = [WCSessionRequestRequest.fromJson(json['params'][0])];
        break;
      case "wc_sessionUpdate":
        params = [WCSessionUpdateRequest.fromJson(json['params'][0])];
        break;
      default:
        params = json['params'];
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'jsonrpc': jsonrpc,
    'method': method,
    'params': params.map((i) => i.toJson()).toList()
  };
}

class JsonRpcResponse {
  final int id;
  final String jsonrpc;
  final dynamic result;

  JsonRpcResponse(this.id, this.jsonrpc, this.result);
  Map<String, dynamic> toJson() => result.runtimeType == ErrorResponse ? 
  {
    'id': id,
    'jsonrpc': jsonrpc,
    'error': result
  }
  :
  {
    'id': id,
    'jsonrpc': jsonrpc,
    'result': result
  };
}

// class InternalEvent {
//   final String event;
//   final List<dynamic> params;

//   InternalEvent(this.event, this.params);

//   Map<String, dynamic> toJson() => {
//     'event': event,
//     'params': params.map((i) => i.toJson()).toList()
//   };
// }