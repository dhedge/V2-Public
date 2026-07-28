// SPDX-License-Identifier: MIT
// solhint-disable
pragma solidity >=0.7.6 <0.9.0;
pragma abicoder v2;

import {Vm} from "forge-std/Vm.sol";
import {HLConstants} from "test/integration/hyperevm/test-suite/hyperevm-lib/lib/HLConstants.sol";

/// @dev Etched at HyperEVM precompile addresses during fork tests.
/// Forwards each call to the real RPC node via `vm.rpc`.
contract PrecompileRpcForwarder {
  Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

  fallback(bytes calldata data) external returns (bytes memory) {
    string memory jsonPayload = string(
      abi.encodePacked('[{"to":"', vm.toString(address(this)), '","data":"', vm.toString(data), '"},"latest"]')
    );
    return vm.rpc("eth_call", jsonPayload);
  }
}

/// @dev Helper to etch PrecompileRpcForwarder at all HyperEVM precompile addresses.
library PrecompileForwarderSetup {
  Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

  function init() internal {
    PrecompileRpcForwarder forwarder = new PrecompileRpcForwarder();
    uint256 codeSize;
    address forwarderAddr = address(forwarder);
    assembly {
      codeSize := extcodesize(forwarderAddr)
    }
    bytes memory code = new bytes(codeSize);
    assembly {
      extcodecopy(forwarderAddr, add(code, 0x20), 0, codeSize)
    }
    for (uint160 i = 0; i < HLConstants.NUM_PRECOMPILES; i++) {
      address precompile = address(uint160(HLConstants.POSITION_PRECOMPILE_ADDRESS) + i);
      vm.etch(precompile, code);
      vm.allowCheatcodes(precompile);
    }
  }
}
