// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IDeathOracle} from "../../src/interface/IDeathOracle.sol";

contract MockDeathOracle is IDeathOracle {
    mapping(bytes32 => bool) public deceased;
    mapping(bytes32 => uint256) public deathTimestamp;
    mapping(bytes32 => bool) public verificationRequested;

    function setDeceased(bytes32 identityHash, bool _deceased) external {
        deceased[identityHash] = _deceased;
        if (_deceased) {
            deathTimestamp[identityHash] = block.timestamp;
        }
    }

    function isPersonDeceased(bytes32 identityHash) external view returns (bool verified, uint256 timestamp) {
        return (deceased[identityHash], deathTimestamp[identityHash]);
    }

    function requestDeathVerification(bytes32 identityHash, bytes calldata) external {
        verificationRequested[identityHash] = true;
    }
}
