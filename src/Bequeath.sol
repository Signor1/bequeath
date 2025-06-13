//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IDeathOracle} from "./interface/IDeathOracle.sol";
import {IPushNotification} from "./interface/IPushNotification.sol";

/**
 * @title Enhanced Bequeathable Asset Registry
 * @dev Comprehensive inheritance system supporting multiple asset types and enhanced security
 * @author Enhanced from ERC-7878 proposal - https://eips.ethereum.org/EIPS/eip-7878
 */

contract Bequeath is AccessControl, ReentrancyGuard, Pausable {}
