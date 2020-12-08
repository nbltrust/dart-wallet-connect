import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:pointycastle/digests/sha3.dart';
import 'package:sprintf/sprintf.dart';

// return a list of [name, symbol, decimals] of ERC20 token
typedef Future<List<dynamic>> ERC20Callback(String address);

class ERC20Cache {
  static ERC20Cache __instance;
  static void createInstance(ERC20Callback cb) {
    __instance = ERC20Cache(cb);
  }
  static ERC20Cache instance() => __instance;

  ERC20Callback callback;
  ERC20Cache(this.callback): cache = {};
  Map<String, List<dynamic>> cache;

  Future<List<dynamic>> getERC20Config(String address) async {
    if(cache.containsKey(address))
      return cache[address];

    cache[address] = await callback(address);
    return cache[address];
  }
}

/// convert address to checksum address
/// 
/// https://github.com/ethereum/EIPs/blob/master/EIPS/eip-55.md
String toChecksumAddress(String hexAddress)
{
    if(hexAddress.startsWith('0x'))
      hexAddress = hexAddress.substring(2);

    var digest = SHA3Digest(256).process(Uint8List.fromList(hexAddress.toLowerCase().codeUnits));
    var hexStr = hex.encode(digest);
    var checksumAddr = '';
    for(var i = 0; i < hexAddress.length; i++) {
      if(int.parse(hexStr[i], radix: 16) >= 8) {
        checksumAddr +=  hexAddress[i].toUpperCase();
      } else {
        checksumAddr += hexAddress[i];
      }
    }
    return '0x' + checksumAddr;
}

class CallTrans {
  String desc_en;
  List<String> translators;

  CallTrans(this.desc_en, this.translators);

  Future<String> doTranslate(String command, BigInt ethVal, String toAddr, Map<String, dynamic> inputArgs) async {
    List<dynamic> stack = [];
    var commands = command.split(' ');
    for(var i = 0; i < commands.length; i++) {
      var op = commands[i];
      // print("${command}: ${op}: ${stack}");
      // command.split(' ').forEach((op) async {
      if(op.startsWith('ARG-')) { // Push argument to stack, e.g. ARG-_spender will push inputArgs['_spender']
        var argName = op.substring(4);
        var arg = inputArgs[argName];
        if(arg is BigInt || arg is num) {
          stack.add(arg.toString());
        } else {
          stack.add(arg);
        }
        continue;
      }

      if(op.startsWith('IMMED-')) { // Push immediate value to stack
        var immedVal = op.substring(6);
        stack.add(immedVal);
        continue;
      }

      if(op.startsWith('LST-')) { // Pop list from stack and push list item back to stack
        var lst = stack.removeLast() as List;
        var idx = int.parse(op.substring(4));
        while(idx < 0) {
          idx += lst.length;
        }

        if(idx >= lst.length) {
          throw Exception("List index out of range");
        }

        stack.add(lst[idx]);
        continue;
      }

      if(op.startsWith('TST')) { // Pop true-value, false-value and bool from stack and push back according to test result
        var condition = stack.removeLast() as bool;
        var falseVal = stack.removeLast() as String;
        var trueVal = stack.removeLast() as String;
        stack.add(condition ? trueVal : falseVal);
        continue;
      }

      if(op == 'TO') { // Push toAddr to top of stack
        stack.add(toAddr);
        continue;
      }

      if(op == 'ETHAMT') { // Push ethVal to top of stack
        stack.add(ethVal.toString());
        continue;
      }

      if(op == 'SYMBOL') { // Pops erc20 address from stack and push back symbol
        var addr = stack.removeLast() as String;
        var cfg = await ERC20Cache.instance().getERC20Config(addr);
        stack.add(cfg[1]);
        continue;
      }

      if(op == 'DECIMAL') { // Pops erc20 address from stack and push back decimal
        var addr = stack.removeLast() as String;
        var cfg = await ERC20Cache.instance().getERC20Config(addr);
        stack.add(cfg[2].toString());
        continue;
      }

      if(op == 'FMTAMT') { // Pops decimal and amount from stack and push back human readable amount
        var decimal = int.parse(stack.removeLast());
        var amount = BigInt.parse(stack.removeLast());
        if(amount == BigInt.parse('ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff', radix: 16)) {
          stack.add('all');
          continue;
        }
        var r = amount / BigInt.from(pow(10, decimal));
        if(r >= 10) {
          stack.add(r.toStringAsFixed(2));
        } else if(r >= 1) {
          stack.add(r.toStringAsFixed(4));
        } else {
          stack.add(r.toStringAsPrecision(6));
        }
        continue;
      }

      if(op == 'FMTADDR') { // Pops address from stack and push back checked encode of address.
        var addr = toChecksumAddress(stack.removeLast() as String);
        stack.add(addr.substring(0, 4) + '...' + addr.substring(addr.length - 4));
        continue;
      }
    }

    if(stack.length != 1) {
      throw Exception("Invalid command");
    }

    return stack[0] as String;
  }

  Future<String> translate(BigInt ethVal, String toAddr, Map<String, dynamic> inputArgs) async {
    List<String> res = [];
    for(var i = 0; i < translators.length; i++) {
      res.add(await doTranslate(translators[i], ethVal, toAddr, inputArgs));
    }
    return sprintf(desc_en, res);
  }
}

class TrxTrans {
  final Map<String, CallTrans> transConfig;

  TrxTrans(String configFile):
    transConfig = Map<String, CallTrans>.fromEntries(
      (jsonDecode(File(configFile).readAsStringSync()) as List)
      .map((i) => MapEntry(i['id'], CallTrans(i['desc_en'], (i['translators'] as List).map((i) => i as String).toList())))
    );


  Future<String> translate(String callId, BigInt ethVal, String toAddr, Map<String, dynamic> inputArgs) async {
    if(!transConfig.containsKey(callId)) {
      throw Exception("unsupported call");
    }

    return await transConfig[callId].translate(ethVal, toAddr, inputArgs);
  }
}
