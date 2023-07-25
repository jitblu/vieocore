import 'dart:io';
import 'dart:convert';
import 'package:vieocore/core/blockchain.dart';
import 'package:vieocore/core/network/p2p.dart';

// Setting up default ports for HTTP communication
int httpPort = int.tryParse(Platform.environment['HTTP_PORT'] ?? '') ?? 3001;

// Function to handle GET requests
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

// Function to handle POST requests
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

// Function to initialize the HTTP server
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
