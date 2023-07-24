// Class representing a block in the blockchain
class Block {
  int index;
  String previousHash;
  int timestamp;
  String data;
  String hash;

  Block(this.index, this.previousHash, this.timestamp, this.data, this.hash);

  // Function to convert a block to JSON format
  Map<String, dynamic> toJson() => {
        'index': index,
        'previousHash': previousHash,
        'timestamp': timestamp,
        'data': data,
        'hash': hash,
      };

  // Function to create a block from JSON data
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
