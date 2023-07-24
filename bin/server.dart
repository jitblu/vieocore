import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:web_socket_channel/io.dart';

int httpPort = int.tryParse(Platform.environment['HTTP_PORT'] ?? '') ?? 3001;
int p2pPort = int.tryParse(Platform.environment['P2P_PORT'] ?? '') ?? 6001;
List<String> initialPeers = Platform.environment['PEERS'] != null
    ? Platform.environment['PEERS']!.split(',')
    : [];

class Block {
  int index;
  String previousHash;
  int timestamp;
  String data;
  String hash;

  Block(this.index, this.previousHash, this.timestamp, this.data, this.hash);

  Map<String, dynamic> toJson() => {
        'index': index,
        'previousHash': previousHash,
        'timestamp': timestamp,
        'data': data,
        'hash': hash,
      };

  factory Block.fromJson(Map<String, dynamic> json) {
    return Block(
      json['index'],
      json['previousHash'],
      json['timestamp'],
      json['data'],
      json['hash'],
    );
  }
}

class Peer {
  final IOWebSocketChannel socket;
  final String address;
  final int port;

  Peer(this.socket, this.address, this.port);
}

List<Peer> sockets = [];

enum MessageType { QUERY_LATEST, QUERY_ALL, RESPONSE_BLOCKCHAIN }

Block getGenesisBlock() {
  return Block(0, "0", 1465154705, "my genesis block!!",
      "816534932c2b7154836da6afc367695e6337db8a921823784c14378abed4f7d7");
}

List<Block> blockchain = [getGenesisBlock()];

void handleGet(HttpRequest request) {
  if (request.uri.path == '/blocks') {
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(blockchain))
      ..close();
  } else if (request.uri.path == '/peers') {
    request.response
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(
          sockets.map((s) => s.address + ':' + s.port.toString()).toList()))
      ..close();
  }
}

void handlePost(HttpRequest request) async {
  if (request.uri.path == '/mineBlock') {
    var content = await utf8.decoder.bind(request).join();
    var data = jsonDecode(content) as Map<String, dynamic>;
    var newBlock = generateNextBlock(data['data']);
    addBlock(newBlock);
    broadcast(responseLatestMsg());
    print('block added: ' + jsonEncode(newBlock));
    request.response
      ..statusCode = HttpStatus.ok
      ..close();
  } else if (request.uri.path == '/addPeer') {
    var content = await utf8.decoder.bind(request).join();
    var data = jsonDecode(content) as Map<String, dynamic>;
    connectToPeers([data['peer']]);
    request.response
      ..statusCode = HttpStatus.ok
      ..close();
  }
}

void initHttpServer() {
  HttpServer.bind(InternetAddress.anyIPv4, httpPort).then((server) {
    server.listen((HttpRequest request) {
      if (request.method == 'GET') {
        handleGet(request);
      } else if (request.method == 'POST') {
        handlePost(request);
      }
    });
  });
}

void initConnection(Peer peer) {
  initMessageHandler(peer.socket);
  initErrorHandler(peer);
  write(peer.socket, queryChainLengthMsg());
}

void initP2PServer() {
  HttpServer.bind(InternetAddress.anyIPv4, p2pPort).then((server) {
    server.listen((HttpRequest request) {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        WebSocketTransformer.upgrade(request).then((socket) {
          var channel = IOWebSocketChannel(socket);
          var address = request.connectionInfo!.remoteAddress.address;
          var port = request.connectionInfo!.remotePort;
          var peer = Peer(channel, address, port);
          sockets.add(peer);
          initConnection(peer);
        });
      }
    });
  });
}

void initMessageHandler(IOWebSocketChannel ws) {
  ws.stream.listen((message) {
    var messageMap = jsonDecode(message);
    print('Received message: $messageMap');
    switch (messageMap['type']) {
      case MessageType.QUERY_LATEST:
        write(ws, responseLatestMsg());
        break;
      case MessageType.QUERY_ALL:
        write(ws, responseChainMsg());
        break;
      case MessageType.RESPONSE_BLOCKCHAIN:
        handleBlockchainResponse(messageMap);
        break;
    }
  });
}

void initErrorHandler(Peer peer) {
  peer.socket.sink.done.catchError((error) {
    closeConnection(peer);
  });
}

void closeConnection(Peer peer) {
  print('connection failed to peer: ${peer.address}:${peer.port}');
  sockets.remove(peer);
}

Block generateNextBlock(String blockData) {
  Block previousBlock = getLatestBlock();
  int nextIndex = previousBlock.index + 1;
  int nextTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  String nextHash =
      calculateHash(nextIndex, previousBlock.hash, nextTimestamp, blockData);
  return Block(
      nextIndex, previousBlock.hash, nextTimestamp, blockData, nextHash);
}

String calculateHashForBlock(Block block) {
  return calculateHash(
      block.index, block.previousHash, block.timestamp, block.data);
}

String calculateHash(
    int index, String previousHash, int timestamp, String data) {
  return sha256
      .convert(utf8.encode('$index$previousHash$timestamp$data'))
      .toString();
}

void addBlock(Block newBlock) {
  if (isValidNewBlock(newBlock, getLatestBlock())) {
    blockchain.add(newBlock);
  }
}

bool isValidNewBlock(Block newBlock, Block previousBlock) {
  if (previousBlock.index + 1 != newBlock.index) {
    print('invalid index');
    return false;
  } else if (previousBlock.hash != newBlock.previousHash) {
    print('invalid previoushash');
    return false;
  } else if (calculateHashForBlock(newBlock) != newBlock.hash) {
    print('invalid hash: ${calculateHashForBlock(newBlock)} ${newBlock.hash}');
    return false;
  }
  return true;
}

void connectToPeers(List<String> newPeers) {
  for (var peerAddress in newPeers) {
    var url = Uri.parse(peerAddress);
    var socket = IOWebSocketChannel.connect(url);
    var peer = Peer(socket, url.host, url.port);
    sockets.add(peer);
    initConnection(peer);
  }
}

void handleBlockchainResponse(Map<String, dynamic> message) {
  List<Block> receivedBlocks = (jsonDecode(message['data']) as List)
      .map((b) => Block.fromJson(b))
      .toList();
  receivedBlocks.sort((b1, b2) => b1.index.compareTo(b2.index));
  Block latestBlockReceived = receivedBlocks.last;
  Block latestBlockHeld = getLatestBlock();
  if (latestBlockReceived.index > latestBlockHeld.index) {
    print(
        'blockchain possibly behind. We got: ${latestBlockHeld.index} Peer got: ${latestBlockReceived.index}');
    if (latestBlockHeld.hash == latestBlockReceived.previousHash) {
      print("We can append the received block to our chain");
      blockchain.add(latestBlockReceived);
      broadcast(responseLatestMsg());
    } else if (receivedBlocks.length == 1) {
      print("We have to query the chain from our peer");
      broadcast(queryAllMsg());
    } else {
      print("Received blockchain is longer than current blockchain");
      replaceChain(receivedBlocks);
    }
  } else {
    print(
        'received blockchain is not longer than current blockchain. Do nothing');
  }
}

void replaceChain(List<Block> newBlocks) {
  if (isValidChain(newBlocks) && newBlocks.length > blockchain.length) {
    print(
        'Received blockchain is valid. Replacing current blockchain with received blockchain');
    blockchain = newBlocks;
    broadcast(responseLatestMsg());
  } else {
    print('Received blockchain invalid');
  }
}

bool isValidChain(List<Block> blockchainToValidate) {
  if (jsonEncode(blockchainToValidate[0]) != jsonEncode(getGenesisBlock())) {
    return false;
  }
  List<Block> tempBlocks = [blockchainToValidate[0]];
  for (int i = 1; i < blockchainToValidate.length; i++) {
    if (isValidNewBlock(blockchainToValidate[i], tempBlocks[i - 1])) {
      tempBlocks.add(blockchainToValidate[i]);
    } else {
      return false;
    }
  }
  return true;
}

Block getLatestBlock() => blockchain.last;
Map<String, dynamic> queryChainLengthMsg() =>
    {'type': MessageType.QUERY_LATEST.index};
Map<String, dynamic> queryAllMsg() => {'type': MessageType.QUERY_ALL.index};
Map<String, dynamic> responseChainMsg() => {
      'type': MessageType.RESPONSE_BLOCKCHAIN.index,
      'data': jsonEncode(blockchain)
    };
Map<String, dynamic> responseLatestMsg() => {
      'type': MessageType.RESPONSE_BLOCKCHAIN.index,
      'data': jsonEncode([getLatestBlock()])
    };

void write(IOWebSocketChannel ws, Map<String, dynamic> message) =>
    ws.sink.add(jsonEncode(message));
void broadcast(Map<String, dynamic> message) =>
    sockets.forEach((peer) => write(peer.socket, message));

void main() {
  connectToPeers(initialPeers);
  initHttpServer();
  initP2PServer();
}
