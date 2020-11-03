import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ethereum_codec/ethereum_codec.dart';
import 'package:convert/convert.dart';
import 'package:eth_abi_codec/eth_abi_codec.dart';
import 'package:sprintf/sprintf.dart';
import 'package:walletconnect/walletconnect.dart';
import 'package:ethereum_util/ethereum_util.dart' show sign, padToEven;

import 'eth_api.dart';

const ETH_DECIMAL = 18;
Map<String, String> descTemplates = {};
const PRIVATE_KEY = '';

String strip0x(String input) {
  return input.startsWith("0x") ? input.substring(2) : input;
}

void initDescTemplates(String templateFile) {
  var f = new File(templateFile);
  var templates = jsonDecode(f.readAsStringSync()) as List;
  templates.forEach((element) {
    descTemplates[element['name']] = element['template'];
  });
}

String getDesc(String templateName, List<String> args) {
  var formatStr = descTemplates[templateName];
  return sprintf(formatStr, args);
}

class ContractMeta {
  String address;
  String contractName;
  Map<String, dynamic> params;

  ContractMeta(this.address, this.contractName, this.params);

  dynamic getParameter(String k) => params[k];

  String toString() => contractName?? '0x' + address;
}

class CallMeta {
  String methodId;
  String functionName;
  Map<String, dynamic> params;

  CallMeta(this.methodId, this.functionName, this.params);
}

class TransactionMeta {
  String type;
  String toAddress;
  String contractName;
  List<String> args;

  TransactionMeta(this.type);

  TransactionMeta setToAddress(String a) {
    toAddress = a;
    return this;
  }

  TransactionMeta setContractName(String c) {
    contractName = c;
    return this;
  }

  TransactionMeta setArgs(List<String> a) {
    args = a;
    return this;
  }

  String toString() => 
    "${type}\n${toAddress}\n${contractName}\n${args}";
}

typedef Future<ContractConfig> getRemoteContractConfig(String address);

Future<ContractConfig> getContractConfig(String addr, {getRemoteContractConfig getRemoteCfg = null}) async {
  if(!addr.startsWith('0x'))
    addr = '0x' + addr;

  var contractCfg = getContractConfigByAddress(addr);
  if(contractCfg == null) {
    if(getRemoteCfg != null) {
      contractCfg = await getRemoteCfg(addr);
    }
  }
  return contractCfg;
}

Future<String> getApproveTarget(Uint8List input) async {
  var call = getContractABIByType('ERC20').decomposeCall(input);
  var spender = call.callParams['_spender'] as String;
  var spenderCfg = await getContractConfig(spender);
  return spenderCfg == null ? null : spenderCfg.symbol;
}

Future<TransactionMeta> getTransactionMeta(
  EthereumTransaction tx,
  getRemoteContractConfig getRemoteCfg) async {
  var h_val = tx.value / BigInt.from(pow(10, ETH_DECIMAL));
  var unknownMeta = TransactionMeta('UNKNOWN')
    .setToAddress(tx.to.toChecksumAddress())
    .setContractName(null)
    .setArgs([hex.encode(tx.input)]);

  if(tx.input.length == 0) {
    return TransactionMeta('ETH transfer')
            .setToAddress(tx.to.toChecksumAddress())
            .setContractName(null)
            .setArgs([h_val.toString(), tx.to.toChecksumAddress()]);
  } else {
    var isApprove = hex.encode(tx.input.sublist(0, 4)) == '095ea7b3';
    var contractCfg = await getContractConfig(tx.to.toString(), getRemoteCfg: getRemoteCfg);
    if(contractCfg == null) {
      // calling to unknown target
      if(isApprove) {
        return TransactionMeta('ERC20 approve')
          .setToAddress(tx.to.toChecksumAddress())
          .setContractName(null)
          .setArgs([await getApproveTarget(tx.input), tx.to.toChecksumAddress()]);
      }
      return unknownMeta;
    }

    var abi = getContractABIByType(contractCfg.type);
    var call_info = ContractCall.fromBinary(tx.input, abi);
    var call_id = '${contractCfg.type} ${call_info.functionName}';
    var meta = TransactionMeta(call_id)
                .setToAddress(tx.to.toChecksumAddress())
                .setContractName(contractCfg.symbol);
    if(call_id == 'ERC20 transfer') {
      var to = call_info.callParams['_to']; // string
      var value = call_info.callParams['_value']; // BigInt
      var precision = int.parse(contractCfg.params['decimal']);
      var amount = value / BigInt.from(pow(10, precision));
      return meta.setArgs([amount.toString(), contractCfg.symbol, to]);
    }

    else if(call_id == 'ERC20 approve') {
      var spender = call_info.callParams['_spender']; // string
      var spenderContract = await getContractConfig(spender);
      if(spenderContract == null) {
        return meta.setArgs([null, contractCfg.symbol]);
      } else {
        return meta.setArgs([spenderContract.symbol, contractCfg.symbol]);
      }
    }

    else if(call_id == 'UNISWAP swapExactETHForTokens') {
      var amountOutMin = call_info.callParams['amountOutMin']; //BigInt
      var outAddr = (call_info.callParams['path'] as List).last;
      var outContract = await getContractConfig(outAddr, getRemoteCfg: getRemoteCfg);
      var toAddr = call_info.callParams['to'];
      if(outContract != null) {
        var precision = int.parse(outContract.params['decimal']);
        var recvAmount = amountOutMin / BigInt.from(pow(10, precision));
        return meta.setArgs([h_val.toString(), recvAmount.toString(), outContract.symbol, toAddr]);
      }
    }

    else if(call_id == 'UNISWAP swapTokensForExactETH') {
      var amountOut = call_info.callParams['amountOut']; //BigInt
      var outAddr = (call_info.callParams['path'] as List).first;
      var outContract = await getContractConfig(outAddr, getRemoteCfg: getRemoteCfg);
      var ethAmount = call_info.callParams['amountInMax'] / BigInt.from(pow(10, ETH_DECIMAL));
      var toAddr = call_info.callParams['to'];
      if(outContract != null) {
        var precision = int.parse(outContract.params['decimal']);
        var outAmount = amountOut / BigInt.from(pow(10, precision));
        return meta.setArgs([outAmount.toString(), outContract.symbol, ethAmount.toString(), toAddr]);
      }
    }

    else if(call_id == 'UNISWAP swapTokensForExactTokens') {
      var amountOut = call_info.callParams['amountOut'];
      var amountInMax = call_info.callParams['amountInMax'];
      var outAddr = (call_info.callParams['path'] as List).first;
      var inAddr = (call_info.callParams['path'] as List).last;
      var outContract = await getContractConfig(outAddr, getRemoteCfg: getRemoteCfg);
      var inContract = await getContractConfig(inAddr, getRemoteCfg: getRemoteCfg);
      var toAddr = call_info.callParams['to'];
      if(outContract != null && inContract != null) {
        var outPrecision = int.parse(outContract.params['decimal']);
        var outAmount = amountOut / BigInt.from(pow(10, outPrecision));
        var inPrecision = int.parse(inContract.params['decimal']);
        var inAmount = amountInMax / BigInt.from(pow(10, inPrecision));
        return meta.setArgs([outAmount.toString(), outContract.symbol, inAmount.toString(), inContract.symbol, toAddr]);
      }
    }

    else if(call_id == 'UNISWAP swapExactTokensForTokens') {
      var amountOutMin = call_info.callParams['amountOutMin'];
      var amountIn = call_info.callParams['amountIn'];
      var inAddr = (call_info.callParams['path'] as List).first;
      var outAddr = (call_info.callParams['path'] as List).last;

      var outContract = await getContractConfig(outAddr, getRemoteCfg: getRemoteCfg);
      var inContract = await getContractConfig(inAddr, getRemoteCfg: getRemoteCfg);
      var toAddr = call_info.callParams['to'];
      if(outContract != null && inContract != null) {
        var outPrecision = int.parse(outContract.params['decimal']);
        var outAmount = amountOutMin / BigInt.from(pow(10, outPrecision));
        var inPrecision = int.parse(inContract.params['decimal']);
        var inAmount = amountIn / BigInt.from(pow(10, inPrecision));
        return meta.setArgs([inAmount.toString(), inContract.symbol, outAmount.toString(), outContract.symbol, toAddr]);
      }
    }

    else if(call_id == 'UNISWAP addLiquidityETH') {
      var amountToken = call_info.callParams['amountTokenDesired'];
      var tokenAddr = call_info.callParams['token'];
      var tokenContract = await getContractConfig(tokenAddr, getRemoteCfg: getRemoteCfg);
      var toAddr = call_info.callParams['to'];
      if(tokenContract != null) {
        var tokenPrecision = int.parse(tokenContract.params['decimal']);
        var tokenAmount = amountToken / BigInt.from(pow(10, tokenPrecision));
        return meta.setArgs([h_val.toString(), tokenAmount.toString(), tokenContract.symbol, toAddr]);
      }
    }

    else if(call_id == 'UNISWAP addLiquidity') {
      var tokenAAddr = call_info.callParams['tokenA'];
      var tokenBAddr = call_info.callParams['tokenB'];
      var tokenAAmount = call_info.callParams['amountADesired'];
      var tokenBAmount = call_info.callParams['amountBDesired'];
      var tokenAContract = await getContractConfig(tokenAAddr, getRemoteCfg: getRemoteCfg);
      var tokenBContract = await getContractConfig(tokenBAddr, getRemoteCfg: getRemoteCfg);
      var toAddr = call_info.callParams['to'];
      if(tokenAContract != null && tokenBContract != null) {
        var tokenAPrecision = int.parse(tokenAContract.params['decimal']);
        var tokenBPrecision = int.parse(tokenBContract.params['decimal']);
        var aAmount = tokenAAmount / BigInt.from(pow(10, tokenAPrecision));
        var bAmount = tokenBAmount / BigInt.from(pow(10, tokenBPrecision));
        return meta.setArgs([aAmount.toString(), tokenAContract.symbol, bAmount.toString(), tokenBContract.symbol, toAddr]);
      }
    }
    print(contractCfg.type);
    print(call_info.toJson());
  }

  return unknownMeta;
}

typedef Future<bool> getUserApprovement();

Future<dynamic> processSendTransaction(Map<String, dynamic> params, getUserApprovement userApproved, getRemoteContractConfig getRemoteCfg) async {
  var from = EthereumAddressHash.fromHex(strip0x(params['from']));
  var to = EthereumAddressHash.fromHex(strip0x(params['to']));
  var value = BigInt.parse(strip0x(params['value']??"0"), radix: 16);
  var gas = int.parse(strip0x(params['gasLimit']??params['gas']), radix: 16);
  var gasPrice = int.parse(strip0x(params['gasPrice']??await EthereumAPI.instance.eth_gasPrice()), radix: 16);
  var data = hex.decode(strip0x(params['data']??""));
  var nonce = int.parse(strip0x(
    params['nonce']??
    await EthereumAPI.instance.eth_getTransactionCount(from.toString(), 'latest')),
    radix: 16);

  EthereumTransaction tx = EthereumTransaction(from, to, value, gas, gasPrice, nonce, input: data);

  print('tx to: ${tx.to.toJson()}');
  print('tx value: ${tx.value}');
  print('tx gas: ${tx.gas}');
  print('tx gas pr: ${tx.gasPrice}');
  print('tx nonce: ${tx.nonce}');
  print('tx input: ${hex.encode(tx.input)}');
  print('tx hashed: ${hex.encode(tx.hashToSign())}');

  var meta = await getTransactionMeta(tx, getRemoteCfg);
  print(meta.toString());
  print(getDesc(meta.type, meta.args));
  if(!(await userApproved())) {
    return ErrorResponse('User rejected');
  } else {
    var sig = sign(tx.hashToSign(), hex.decode(PRIVATE_KEY), chainId: 1);
    tx.sigR = hex.decode(padToEven(sig.r.toRadixString(16)));
    tx.sigS = hex.decode(padToEven(sig.s.toRadixString(16)));
    tx.sigV = sig.v;

    print('encoded: ${hex.encode(tx.toRlp())}');
    try {
      var resp = await EthereumAPI.instance.eth_sendRawTransaction('0x' + hex.encode(tx.toRlp()));
      return resp;
    } catch (e) {
      return ErrorResponse(e);
    }
  }
}

Future<dynamic> processEthJsonRpcCall(String method, Map<String, dynamic> params, getUserApprovement userApproved, {getRemoteContractConfig getRemoteCfg = null}) {
  if(method == 'eth_sendTransaction') {
    return processSendTransaction(params, userApproved, getRemoteCfg);
  }
  return null;
}
