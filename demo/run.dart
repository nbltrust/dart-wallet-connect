import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:ethereum_codec/ethereum_codec.dart';
import 'package:walletconnect/walletconnect.dart';

import 'eth_api.dart';
import 'ethereum.dart';

String readUserInput(String hint, List<String> selections) {
  stdout.write(hint);
  for(var i = 0; i < selections.length; i++) {
    stdout.write("${i + 1}. ${selections[i]}\n");
  }

  while(true) {
    stdout.write('Input selection: ');
    var line = stdin.readLineSync(encoding: Encoding.getByName('utf-8'));
    var sel = int.parse(line.trim());
    if(sel >= 1 && sel <= selections.length){
      return selections[sel - 1];
    }
  }
}

var inputController = new StreamController<String>.broadcast();

Future<String> readUserInputAsync(String hint, List<String> selections) async {
  stdout.write(hint);
  for(var i = 0; i < selections.length; i++) {
    stdout.write("${i + 1}. ${selections[i]}\n");
  }

  var sel = int.parse(await inputController.stream.first);
  if(sel >= 1 && sel <= selections.length) {
    return selections[sel - 1];
  }
  return '';
}

Future<String> callInfura(String to, String data) async {
  return await EthereumAPI.instance.eth_call({"to": to, "data": data}, "latest");
}

void main(List<String> args) async {
  var wc_cli = WalletConnectClient.fromURI(args[0]);

  var myStdIn = stdin.transform(utf8.decoder).transform(new LineSplitter());
  myStdIn.listen(inputController.add);

  EthereumAPI.createInstance('https://mainnet.infura.io');
  initContractABIs('contract_abi');
  initDescTemplates('trx_info_template.json');

  wc_cli.setCallback((req) async {
    switch(req.method) {
      case "wc_sessionRequest":
        var p = req.params[0] as WCSessionRequestRequest;
        print('Remote peer id: ${p.peerId}');
        print('Remote chain id: ${p.chainId}');
        print('Remote name: ${p.peerMeta.name}');
        print('Remote description: ${p.peerMeta.description}');
        print('Remote url: ${p.peerMeta.url}');
        print('Remote icons: ${p.peerMeta.icons}');

        wc_cli.setDappPeerId(p.peerId);

        var wallet_address = '0x621B2B1e5e1364fB014C5232E2bC9d30dd46c1f0';
        var resp = null;
        var sel = await readUserInputAsync("Approve this wallet?\n", ["approve", "reject"]);
        if(sel == "approve")
        {// user clicked approve
          resp = WCSessionRequestResponse(
            wc_cli.client_peer_id,
            ClientMeta('www.baidu.com', 'hashkey test', 'description of hashkey test', ['https://prime.hashkey.com/logo_title.svg']),
            true,
            1,
            [wallet_address]
          );
          wc_cli.sendResponse(JsonRpcResponse(req.id, req.jsonrpc, resp));
        } else { // user clicked reject
          resp = ErrorResponse('client reject');
          wc_cli.sendResponse(JsonRpcResponse(req.id, req.jsonrpc, resp));
          wc_cli.disconnect();
        }
        break;
      default:
        if(req.method.startsWith("eth_")) {
          var resp = await processEthJsonRpcCall(req.method, req.params[0], 
            () async => (await readUserInputAsync("Approve?\n", ["approve", "reject"])) == "approve",
            getRemoteCfg: (address) async {
              // getRemoteCfg need to return a configuration of given address
              // we just assume address is ERC20
              var abi = getContractABIByType('ERC20');
              var r1 = await callContractByAbi(abi, address, 'name', {}, callInfura);
              var name = r1[''];

              var r2 = await callContractByAbi(abi, address, 'decimals', {}, callInfura);
              // as in contract_symbols.json, decimals are configured as string
              // we convert it to string for compatibility
              var decimal = r2[''].toString();
              return ContractConfig(address, name, 'ERC20', {'decimal': decimal});
            });

          print('get response ${resp}');
          if(resp != null) {
            var r = JsonRpcResponse(
              req.id,
              req.jsonrpc,
              resp);
            wc_cli.sendResponse(r);
          }
        }
    }
    // print(method);
    // print(params);
  });

  // Timer(Duration(seconds: 10), () {
  //   wc_cli.disconnect();
  // });
  await wc_cli.run();
}