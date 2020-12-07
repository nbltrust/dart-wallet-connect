// import 'dart:convert';
// import 'package:walletconnect/walletconnect.dart';
import 'package:test/test.dart';

import 'package:dio/dio.dart';
import 'package:walletconnect/src/util/trx_trans.dart';
import 'package:ethereum_codec/ethereum_codec.dart';
import 'package:eth_abi_codec/eth_abi_codec.dart';
import 'package:convert/convert.dart';

// import 'eth_api.dart';

Future<dynamic> callInfura(String method, List<dynamic> params) async {
  var dio = new Dio();
  // print(method);
  // print(params);
  var response = await dio.post(
    'https://mainnet.infura.io/v3/774b1e4252de48c3997d66ac5f5078d8',
    data: {
      'id': 1,
      'jsonrpc': '2.0',
      'method': method,
      'params': params
    });
  // print(response.data);
  return response.data;
}

Future<String> ethCall(String to, String data) async {
  var res = await callInfura('eth_call', [{'to': to, 'data': data}, 'latest']);
  if((res as Map).containsKey('error')) {
    throw Exception("Call contract error");
  }
  return res['result'] as String;
}

Future<List<dynamic>> getERC20Config(String address) async {
  var res = await aggregateCallContract([
    ['ERC20', address, 'name', Map<String, dynamic>()],
    ['ERC20', address, 'symbol', Map<String, dynamic>()],
    ['ERC20', address, 'decimals', Map<String, dynamic>()]],
    ethCall);
  var name = res[0][''];
  var symbol = res[1][''];
  var decimal = res[2][''];
  return [name, symbol, decimal];
}

Future<String> runTranslate(TrxTrans translator, String trxId) async {
  var trx = await callInfura('eth_getTransactionByHash', [trxId]);
  if(trx['result']['input'] != '0x') {
    var cfg = getContractConfigByAddress(trx['result']['to']);
    if(cfg == null) {
      print('Contract not configured, ${trx["result"]["to"]}');
      return '';
    } else {
      print('Contract Type ${cfg.type}');
    }
    var abi = getContractABIByType(cfg.type);
    if(abi == null) {
      print('Contract ABI not configured, ${cfg.type}');
      return '';
    }

    var callInfo = ContractCall.fromBinary(hex.decode((trx['result']['input'] as String).substring(2)), abi);
    var methodId = '${cfg.type}_${callInfo.functionName}';
    // print('Method id: ${methodId}');
    // print('Method params: ${callInfo.callParams}');
    return await translator.translate(
          methodId,
          BigInt.parse(trx['result']['value'].substring(2), radix: 16), 
          trx['result']['to'],
          callInfo.callParams
          );
  } else {
    return await translator.translate(
          'ETH_transfer',
          BigInt.parse(trx['result']['value'].substring(2), radix: 16), 
          trx['result']['to'],
          {}
          );
  }
}

void main() async {
  initContractABIs('contract_abi');
  ERC20Cache.createInstance(getERC20Config);
  var translator = TrxTrans('trx_trans.config.json');

  // test('test ETH transfer', () async {
  //   expect(
  //     await runTranslate(translator, '0x6a87019b97c81356af1e249db5f02d280635667d7092a9be2725ae302592bb3a'),
  //     'Transfer 0.0986045 ETH to 0xA88170E2142b0e1EeFCB2041B7f3754f4F4298Fd'
  //   );
  // });

  // test('test ERC20 approve ulimited', () async {
  //   expect(
  //     await runTranslate(translator, '0x493aadbfe79cd624ac05fa36e7ae224f57ec44327ea5cdbc11448a263428d599'), 
  //     'Approve 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D use unlimited aDAI');
  // });

  // test('test UNISWAP swapETHForExactTokens', () async {
  //   expect(
  //     await runTranslate(translator, '0x71665eec814d811c0dfc9488566bc7dbde73616f6f3ea2e1b81b1626f0f0011d'),
  //     'swap 0.00167330 ETH for 1.0000 DAI to 0xA88170E2142b0e1EeFCB2041B7f3754f4F4298Fd');
  // });

  // test('test UNISWAP swapExactTokensForTokens', () async {
  //   expect(
  //     await runTranslate(translator, '0x413d85b2040c4fad56b87fc1b4984f8fa0b32499e388cc0c7b669f8fe85de115'),
  //     'swap 0.0915967 aDAI for 0.000158257 WETH to 0xA88170E2142b0e1EeFCB2041B7f3754f4F4298Fd'
  //   );
  // });

  // test('test UNISWAP swapExactETHForTokens', () async {
  //   expect(
  //     await runTranslate(translator, '0xdfb2cc7617702f845d642475a50fa5c782eba814824165490eab3c660a14ed36'),
  //     'swap 0.0100000 ETH for 0.000319010 WBTC to 0xA88170E2142b0e1EeFCB2041B7f3754f4F4298Fd');
  // });

  test('test UNISWAP swapExactTokensForETH', () async {
    expect(
      await runTranslate(translator, '0x43389c13577235582077487cda4bb7e6298b3829dc93f22dff4dab354575900c'),
      'swap 0.306831 OMG for 0.00212369 ETH to 0xA88170E2142b0e1EeFCB2041B7f3754f4F4298Fd');
  });

  // test('test UNISWAP addLiquidityETH', () async {
  //   expect(
  //     await runTranslate(translator, '0xee42575e7a9eecacf1b907f4b0ffba6c38141a187d3ba6845ee5ef6e6765fa24'),
  //     'add 1.0436 ETH and 573199.08 COL to 0x98bc770EacA22E94942Eb74dE6040d8467225795'
  //   );
  // });
}