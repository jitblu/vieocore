import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:vieocore/core/models/block.dart';
import 'package:vieocore/core/network/p2p.dart';

// Function to get the genesis block
Block getGenesisBlock() {
  return Block(0, "0", 1465154705, "my genesis block!!",
      "816534932c2b7154836da6afc367695e6337db8a921823784c14378abed4f7d7");
}

// The blockchain, initialized with the genesis block
List<Block> blockchain = [getGenesisBlock()];

// Function to generate the next block in the chain
Block generateNextBlock(String blockData) {
  Block previousBlock = getLatestBlock();
  int nextIndex = previousBlock.index + 1;
  int nextTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  String nextHash =
      calculateHash(nextIndex, previousBlock.hash, nextTimestamp, blockData);
  return Block(
      nextIndex, previousBlock.hash, nextTimestamp, blockData, nextHash);
}

// Function to calculate the hash for a block
String calculateHashForBlock(Block block) {
  return calculateHash(
      block.index, block.previousHash, block.timestamp, block.data);
}

// Function to calculate a hash
String calculateHash(
    int index, String previousHash, int timestamp, String data) {
  return sha256
      .convert(utf8.encode('$index$previousHash$timestamp$data'))
      .toString();
}

// Function to add a block to the blockchain
void addBlock(Block newBlock) {
  if (isValidNewBlock(newBlock, getLatestBlock())) {
    blockchain.add(newBlock);
  }
}

// Function to validate a new block
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

// Function to replace the current blockchain with a new one
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

// Function to validate a blockchain
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

// Function to get the latest block in the blockchain
Block getLatestBlock() => blockchain.last;
