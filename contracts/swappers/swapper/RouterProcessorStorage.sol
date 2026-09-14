//
//    ===========  ======     ======         =         ====          ====   =========    ==========   ==========
//   ==        ==    ===        ==          ===          ===         ===     ==    ==     ===    ==     ==   ====
// ===          =    ===        ==         = ===         ====       ====     ==    ==     ===           ==    ===
// ====              =============        =   ===        = ===    == ===     ========     ========      =======
// ====              ===        ==       =========       =  ===  ==  ===     ==    ===    ===    =      ==  ===
// ==                ===        ==      =       ===      =   === ==  ===     ==     ===   ===           ==   ===
//   ===       ==    ===        ==     ==        ====    =    ===    ===     ==     ==    ===     ==    ==     ====
//     ==========  ======     ====== =====       ===== ====    ==    ====  ==========    ===========  ======     ====
//
// Chamber Finance - https://chamberfi.com
//
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

abstract contract RouterProcessorStorage {
  /// @custom:storage-location erc7201:Swapper.RouterProcessor
  struct RouterProcessorStorageData {
    mapping(bytes32 routerKey => address routerAddress) routers;
  }

  // keccak256(abi.encode(uint256(keccak256("Swapper.RouterProcessor")) - 1)) & ~bytes32(uint256(0xff))
  bytes32 private constant _ROUTER_PROCESSOR_STORAGE_LOCATION =
    0x4cf853a34ccdbeaaf639a4ff5f4912cf72bb597aabb8eb66c2a38478d7f72300;

  function getRouter(bytes32 routerKey_) public view returns (address routerAddress_) {
    return _getRouterProcessorStorage().routers[routerKey_];
  }

  function _addRouter(bytes32 routerKey_, address router_) internal {
    _getRouterProcessorStorage().routers[routerKey_] = router_;
  }

  function _removeRouter(bytes32 routerKey_) internal {
    delete _getRouterProcessorStorage().routers[routerKey_];
  }

  function _getRouterProcessorStorage() private pure returns (RouterProcessorStorageData storage $) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      $.slot := _ROUTER_PROCESSOR_STORAGE_LOCATION
    }
  }
}
