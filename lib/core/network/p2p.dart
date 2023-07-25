import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/io.dart';
import 'package:vieocore/core/models/block.dart';
import 'package:vieocore/core/models/peer.dart';
import 'package:vieocore/core/blockchain.dart';

// Setting up default ports for P2P communication
int p2pPort = int.tryParse(Platform.environment['P2P_PORT'] ?? '') ?? 6001;

// List of initial peers if any
List<String> initialPeers = Platform.environment['PEERS'] != null
    ? Platform.environment['PEERS']!.split(',')
    : [];

// List of connected peers
List<Peer> sockets = [];

// Enum representing the types of messages that can be sent in the network
enum MessageType { QUERY_LATEST, QUERY_ALL, RESPONSE_BLOCKCHAIN }

// Function to initialize a connection with a peer
void initConnection(Peer peer) {
  initMessageHandler(peer.socket);
  initErrorHandler(peer);
  write(peer.socket, queryChainLengthMsg());
}

// Function to close a connection with a peer
void closeConnection(Peer peer) {
  print('connection failed to peer: ${peer.address}:${peer.port}');
  sockets.remove(peer);
}

// Function to connect to new peers
void connectToPeers(List<String> newPeers) {
  for (var peerAddress in newPeers) {
    var url = Uri.parse(peerAddress);
    var socket = IOWebSocketChannel.connect(url);
    var peer = Peer(socket, url.host, url.port);
    sockets.add(peer);
    initConnection(peer);
  }
}

// Function to handle the response from the blockchain
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

// Function to initialize the message handler for a socket
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

// Function to initialize the error handler for a peer
void initErrorHandler(Peer peer) {
  peer.socket.sink.done.catchError((error) {
    closeConnection(peer);
  });
}

// Function to initialize the P2P server
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

// Function to create a message querying the length of the chain
Map<String, dynamic> queryChainLengthMsg() =>
    {'type': MessageType.QUERY_LATEST.index};

// Function to create a message querying all blocks
Map<String, dynamic> queryAllMsg() => {'type': MessageType.QUERY_ALL.index};

// Function to create a message with the entire blockchain
Map<String, dynamic> responseChainMsg() => {
      'type': MessageType.RESPONSE_BLOCKCHAIN.index,
      'data': jsonEncode(blockchain)
    };

// Function to create a message with the latest block
Map<String, dynamic> responseLatestMsg() => {
      'type': MessageType.RESPONSE_BLOCKCHAIN.index,
      'data': jsonEncode([getLatestBlock()])
    };

// Function to write a message to a socket
void write(IOWebSocketChannel ws, Map<String, dynamic> message) =>
    ws.sink.add(jsonEncode(message));

// Function to broadcast a message to all peers
void broadcast(Map<String, dynamic> message) =>
    sockets.forEach((peer) => write(peer.socket, message));
