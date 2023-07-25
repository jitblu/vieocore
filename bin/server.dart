// Importing necessary libraries
import 'package:vieocore/core/network/p2p.dart';
import 'package:vieocore/core/network/http.dart';

// Main function
void main() {
  connectToPeers(initialPeers);
  initHttpServer();
  initP2PServer();
}
