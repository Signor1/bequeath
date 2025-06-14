// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Bequeath} from "../src/Bequeath.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockDeathOracle} from "./mock/MockDeathOracle.sol";
import {MockPushNotification} from "./mock/MockPushNotification.sol";
import {MockERC721} from "./mock/MockERC721.sol";
import {MockERC1155} from "./mock/MockERC1155.sol";

contract BequeathTest is Test {
    Bequeath public bequeath;
    MockDeathOracle public deathOracle;
    MockPushNotification public pushNotification;
    ERC20Mock public token;
    MockERC721 public nft;
    MockERC1155 public multiToken;

    address public owner = address(0x1);
    address public executor1 = address(0x2);
    address public executor2 = address(0x3);
    address public beneficiary1 = address(0x4);
    address public beneficiary2 = address(0x5);
    address public nonParticipant = address(0x6);

    bytes32 public constant IDENTITY_HASH = keccak256("owner_identity");

    function setUp() public {
        // Deploy mock contracts
        deathOracle = new MockDeathOracle();
        pushNotification = new MockPushNotification();
        token = new ERC20Mock();
        nft = new MockERC721();
        multiToken = new MockERC1155();

        // Deploy main contract
        bequeath = new Bequeath(address(deathOracle), address(pushNotification));

        // Setup test accounts with ETH
        vm.deal(owner, 100 ether);
        vm.deal(executor1, 1 ether);
        vm.deal(executor2, 1 ether);
        vm.deal(beneficiary1, 1 ether);
        vm.deal(beneficiary2, 1 ether);

        // Mint test tokens
        token.mint(owner, 1000 ether);
        nft.mint(owner);
        nft.mint(owner);
        multiToken.mint(owner, 1, 100);
        multiToken.mint(owner, 2, 200);
    }

    function testCreateWill() public {
        vm.startPrank(owner);

        address[] memory executors = new address[](2);
        executors[0] = executor1;
        executors[1] = executor2;

        Bequeath.Beneficiary[] memory beneficiaries = new Bequeath.Beneficiary[](2);
        beneficiaries[0] = Bequeath.Beneficiary({
            beneficiaryAddress: beneficiary1,
            percentage: 6000, // 60%
            description: "Primary beneficiary"
        });
        beneficiaries[1] = Bequeath.Beneficiary({
            beneficiaryAddress: beneficiary2,
            percentage: 4000, // 40%
            description: "Secondary beneficiary"
        });

        bequeath.createWill(executors, beneficiaries, 7 days, IDENTITY_HASH, false);

        Bequeath.Will memory will = bequeath.getWill(owner);
        assertEq(will.owner, owner);
        assertEq(will.executors.length, 2);
        assertEq(will.beneficiaries.length, 2);
        assertEq(will.moratoriumPeriod, 7 days);
        assertEq(uint256(will.status), uint256(Bequeath.WillStatus.Active));

        vm.stopPrank();
    }

    function testCreateWillWithInvalidPercentages() public {
        vm.startPrank(owner);

        address[] memory executors = new address[](2);
        executors[0] = executor1;
        executors[1] = executor2;

        Bequeath.Beneficiary[] memory beneficiaries = new Bequeath.Beneficiary[](2);
        beneficiaries[0] = Bequeath.Beneficiary({
            beneficiaryAddress: beneficiary1,
            percentage: 5000, // 50%
            description: "Primary beneficiary"
        });
        beneficiaries[1] = Bequeath.Beneficiary({
            beneficiaryAddress: beneficiary2,
            percentage: 3000, // 30% (total = 80%, should fail)
            description: "Secondary beneficiary"
        });

        vm.expectRevert("Beneficiary percentages must sum to 100%");
        bequeath.createWill(executors, beneficiaries, 7 days, IDENTITY_HASH, false);

        vm.stopPrank();
    }

    function testDepositETH() public {
        _createBasicWill();

        vm.startPrank(owner);

        uint256 depositAmount = 10 ether;
        bequeath.depositETH{value: depositAmount}();

        assertEq(bequeath.getETHBalance(owner), depositAmount);

        Bequeath.Asset[] memory assets = bequeath.getAssets(owner);
        assertEq(assets.length, 1);
        assertEq(uint256(assets[0].assetType), uint256(Bequeath.AssetType.ETH));
        assertEq(assets[0].amount, depositAmount);
        assertTrue(assets[0].isDeposited);

        vm.stopPrank();
    }

    // ========== Helper Functions =============
    function _createBasicWill() internal {
        vm.startPrank(owner);

        address[] memory executors = new address[](2);
        executors[0] = executor1;
        executors[1] = executor2;

        Bequeath.Beneficiary[] memory beneficiaries = new Bequeath.Beneficiary[](2);
        beneficiaries[0] = Bequeath.Beneficiary({
            beneficiaryAddress: beneficiary1,
            percentage: 6000, // 60%
            description: "Primary beneficiary"
        });
        beneficiaries[1] = Bequeath.Beneficiary({
            beneficiaryAddress: beneficiary2,
            percentage: 4000, // 40%
            description: "Secondary beneficiary"
        });

        bequeath.createWill(executors, beneficiaries, 7 days, IDENTITY_HASH, false);

        vm.stopPrank();
    }

    function _createWillWithOracle() internal {
        vm.startPrank(owner);

        address[] memory executors = new address[](2);
        executors[0] = executor1;
        executors[1] = executor2;

        Bequeath.Beneficiary[] memory beneficiaries = new Bequeath.Beneficiary[](2);
        beneficiaries[0] = Bequeath.Beneficiary({
            beneficiaryAddress: beneficiary1,
            percentage: 6000, // 60%
            description: "Primary beneficiary"
        });
        beneficiaries[1] = Bequeath.Beneficiary({
            beneficiaryAddress: beneficiary2,
            percentage: 4000, // 40%
            description: "Secondary beneficiary"
        });

        bequeath.createWill(
            executors,
            beneficiaries,
            7 days,
            IDENTITY_HASH,
            true // Requires oracle verification
        );

        vm.stopPrank();
    }

    function _depositTestAssets() internal {
        vm.startPrank(owner);

        // Deposit ETH
        bequeath.depositETH{value: 10 ether}();

        // Deposit ERC20
        token.approve(address(bequeath), 500 ether);
        bequeath.depositERC20(address(token), 500 ether);

        vm.stopPrank();
    }
}
