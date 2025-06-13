// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @author  death-oracle (Proposed Death Oracle)
 * @title   Proposed Death Oracle Interface
 * @dev     This interface defines the functions for a death oracle that verifies if a person is deceased.
 * @notice  The oracle allows querying the death status of a person based on their identity hash and provides a mechanism to request death verification with evidence.
 */
interface IDeathOracle {
    /**
     * @notice Checks if a person is deceased based on their identity hash.
     * @param identityHash The hash of the person's identity.
     * @return verified A boolean indicating if the person is verified as deceased.
     * @return timestamp The timestamp of when the death was verified.
     */
    function isPersonDeceased(bytes32 identityHash) external view returns (bool verified, uint256 timestamp);

    /**
     * @notice Requests verification of a person's death with evidence.
     * @param identityHash The hash of the person's identity.
     * @param evidence The evidence provided for the death verification.
     */
    function requestDeathVerification(bytes32 identityHash, bytes calldata evidence) external;
}
