// SPDX-License-Identifier: UNLICENSED
// See https://github.com/storyprotocol/protocol-contracts/blob/main/StoryProtocol-AlphaTestingAgreement-17942166.3.pdf
pragma solidity ^0.8.23;

import { IModule } from "./IModule.sol";

/// @notice Hook Module Interface
interface IViewModule is IModule {
    /// @notice check whether the view module is supported for the given IP account
    function isSupported(address ipAccount) external returns (bool);
}
