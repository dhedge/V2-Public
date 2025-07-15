// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IGmxEvent {
  struct EventLogData {
    AddressItems addressItems;
    UintItems uintItems;
    IntItems intItems;
    BoolItems boolItems;
    Bytes32Items bytes32Items;
    BytesItems bytesItems;
    StringItems stringItems;
  }

  struct AddressItems {
    AddressKeyValue[] items;
    AddressArrayKeyValue[] arrayItems;
  }
  struct AddressKeyValue {
    string key;
    address value;
  }

  struct AddressArrayKeyValue {
    string key;
    address[] value;
  }

  struct UintItems {
    UintKeyValue[] items;
    UintArrayKeyValue[] arrayItems;
  }

  struct UintKeyValue {
    string key;
    uint256 value;
  }

  struct UintArrayKeyValue {
    string key;
    uint256[] value;
  }

  struct IntKeyValue {
    string key;
    int256 value;
  }

  struct IntArrayKeyValue {
    string key;
    int256[] value;
  }

  struct IntItems {
    IntKeyValue[] items;
    IntArrayKeyValue[] arrayItems;
  }

  struct BoolItems {
    BoolKeyValue[] items;
    BoolArrayKeyValue[] arrayItems;
  }

  struct BoolKeyValue {
    string key;
    bool value;
  }

  struct BoolArrayKeyValue {
    string key;
    bool[] value;
  }

  struct Bytes32Items {
    Bytes32KeyValue[] items;
    Bytes32ArrayKeyValue[] arrayItems;
  }

  struct Bytes32KeyValue {
    string key;
    bytes32 value;
  }

  struct Bytes32ArrayKeyValue {
    string key;
    bytes32[] value;
  }

  struct BytesItems {
    BytesKeyValue[] items;
    BytesArrayKeyValue[] arrayItems;
  }

  struct StringItems {
    StringKeyValue[] items;
    StringArrayKeyValue[] arrayItems;
  }

  struct BytesKeyValue {
    string key;
    bytes value;
  }

  struct BytesArrayKeyValue {
    string key;
    bytes[] value;
  }

  struct StringKeyValue {
    string key;
    string value;
  }

  struct StringArrayKeyValue {
    string key;
    string[] value;
  }
}
