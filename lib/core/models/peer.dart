import 'package:web_socket_channel/io.dart';

// Class representing a peer in the network
class Peer {
  final IOWebSocketChannel socket;
  final String address;
  final int port;

  Peer(this.socket, this.address, this.port);
}
