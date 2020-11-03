import 'package:dio/dio.dart';
import 'package:ethereum_codec/ethereum_codec.dart';
import 'dart:mirrors';

class EthereumAPI {
  static EthereumAPI _instance;
  static void createInstance(String endpoint) {
    _instance = EthereumAPI(endpoint);
  }

  static dynamic get instance => _instance;

  String endpoint;
  Dio dio;
  EthereumAPI(this.endpoint) {
    dio = new Dio();
    dio.options.baseUrl = this.endpoint;
    dio.options.headers = {'Connection': 'keep-alive'};
    dio.options.baseUrl = 'https://mainnet.infura.io';
  }

  @override
  noSuchMethod(Invocation invocation) async {
    var response = await dio.post(
      '/v3/774b1e4252de48c3997d66ac5f5078d8', 
      data: {
        'jsonrpc': '2.0',
        'method': MirrorSystem.getName(invocation.memberName),
        'id': 1,
        'params': invocation.positionalArguments
      });

    if(response.statusCode != 200) {
      throw "status code error";
    }
    if(response.data.containsKey('error')) {
      throw response.data['error']['message'];
    }
    return response.data['result'];
  }
}

void main() async {
  initContractABIs('contract_abi');
  EthereumAPI.createInstance('https://mainnet.infura.io');
  print(await EthereumAPI.instance.eth_protocolVersion());
  print(await EthereumAPI.instance.eth_hashrate());
  print(await EthereumAPI.instance.eth_gasPrice());

  print(await EthereumAPI.instance.eth_getBalance('0x621b2b1e5e1364fb014c5232e2bc9d30dd46c1f0', 'latest'));
  print(await EthereumAPI.instance.eth_getTransactionCount('0x621b2b1e5e1364fb014c5232e2bc9d30dd46c1f0', 'latest'));
}