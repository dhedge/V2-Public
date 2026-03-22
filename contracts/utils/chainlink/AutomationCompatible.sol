// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AutomationBase} from "./AutomationBase.sol";
import {AutomationCompatibleInterface} from "./interfaces/AutomationCompatibleInterface.sol";

// solhint-disable-next-line no-empty-blocks
abstract contract AutomationCompatible is AutomationBase, AutomationCompatibleInterface {}
