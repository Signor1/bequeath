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

    function testDepositERC20() public {
        _createBasicWill();

        vm.startPrank(owner);

        uint256 depositAmount = 500 ether;
        token.approve(address(bequeath), depositAmount);
        bequeath.depositERC20(address(token), depositAmount);

        assertEq(bequeath.getERC20Balance(owner, address(token)), depositAmount);

        Bequeath.Asset[] memory assets = bequeath.getAssets(owner);
        assertEq(assets.length, 1);
        assertEq(uint256(assets[0].assetType), uint256(Bequeath.AssetType.ERC20));
        assertEq(assets[0].contractAddress, address(token));
        assertEq(assets[0].amount, depositAmount);

        vm.stopPrank();
    }

    function testDepositERC721() public {
        _createBasicWill();

        vm.startPrank(owner);

        uint256 tokenId = 0;
        nft.approve(address(bequeath), tokenId);
        bequeath.depositERC721(address(nft), tokenId);

        uint256[] memory holdings = bequeath.getERC721Holdings(owner, address(nft));
        assertEq(holdings.length, 1);
        assertEq(holdings[0], tokenId);

        assertEq(nft.ownerOf(tokenId), address(bequeath));

        vm.stopPrank();
    }

    function testDepositERC1155() public {
        _createBasicWill();

        vm.startPrank(owner);

        uint256 tokenId = 1;
        uint256 amount = 50;
        multiToken.setApprovalForAll(address(bequeath), true);
        bequeath.depositERC1155(address(multiToken), tokenId, amount);

        assertEq(bequeath.getERC1155Balance(owner, address(multiToken), tokenId), amount);

        vm.stopPrank();
    }

    function testWithdrawETH() public {
        _createBasicWill();

        vm.startPrank(owner);

        uint256 depositAmount = 10 ether;
        bequeath.depositETH{value: depositAmount}();

        uint256 withdrawAmount = 5 ether;
        uint256 balanceBefore = owner.balance;

        bequeath.withdrawETH(withdrawAmount);

        assertEq(owner.balance, balanceBefore + withdrawAmount);
        assertEq(bequeath.getETHBalance(owner), depositAmount - withdrawAmount);

        vm.stopPrank();
    }

    function testWithdrawERC20() public {
        _createBasicWill();

        vm.startPrank(owner);

        uint256 depositAmount = 500 ether;
        token.approve(address(bequeath), depositAmount);
        bequeath.depositERC20(address(token), depositAmount);

        uint256 withdrawAmount = 200 ether;
        uint256 balanceBefore = token.balanceOf(owner);

        bequeath.withdrawERC20(address(token), withdrawAmount);

        assertEq(token.balanceOf(owner), balanceBefore + withdrawAmount);
        assertEq(bequeath.getERC20Balance(owner, address(token)), depositAmount - withdrawAmount);

        vm.stopPrank();
    }

    function testAnnounceInheritance() public {
        _createBasicWill();
        _depositTestAssets();

        vm.startPrank(executor1);

        bequeath.announceInheritance(owner);

        Bequeath.InheritanceProcess memory process = bequeath.getInheritanceProcess(owner);
        assertEq(process.initiator, executor1);
        assertEq(uint256(process.status), uint256(Bequeath.ProcessStatus.Announced));
        assertTrue(process.oracleVerified); // Should be true for non-oracle wills

        vm.stopPrank();
    }

    function testAnnounceInheritanceWithOracle() public {
        _createWillWithOracle();
        _depositTestAssets();

        // Set person as deceased in oracle
        deathOracle.setDeceased(IDENTITY_HASH, true);

        vm.startPrank(executor1);

        bequeath.announceInheritance(owner);

        Bequeath.InheritanceProcess memory process = bequeath.getInheritanceProcess(owner);
        assertEq(process.initiator, executor1);
        assertEq(uint256(process.status), uint256(Bequeath.ProcessStatus.Announced));
        assertTrue(process.oracleVerified);

        vm.stopPrank();
    }

    function testProvideConsensus() public {
        _createBasicWill();
        _depositTestAssets();

        vm.prank(executor1);
        bequeath.announceInheritance(owner);

        vm.prank(executor1);
        bequeath.provideConsensus(owner);

        vm.prank(executor2);
        bequeath.provideConsensus(owner);

        Bequeath.InheritanceProcess memory process = bequeath.getInheritanceProcess(owner);
        assertEq(process.executorConsensusCount, 2);
    }

    function testChallengeInheritance() public {
        _createBasicWill();
        _depositTestAssets();

        vm.prank(executor1);
        bequeath.announceInheritance(owner);

        vm.prank(executor2);
        bequeath.challengeInheritance(owner, "Suspicious circumstances");

        Bequeath.InheritanceProcess memory process = bequeath.getInheritanceProcess(owner);
        assertEq(uint256(process.status), uint256(Bequeath.ProcessStatus.Challenged));
        assertEq(process.challengers.length, 1);
        assertEq(process.challengers[0], executor2);
    }

    function testExecuteInheritance() public {
        _createBasicWill();
        _depositTestAssets();

        // Announce inheritance
        vm.prank(executor1);
        bequeath.announceInheritance(owner);

        // Provide consensus
        vm.prank(executor1);
        bequeath.provideConsensus(owner);
        vm.prank(executor2);
        bequeath.provideConsensus(owner);

        // Skip moratorium and challenge period
        vm.warp(block.timestamp + 7 days + 3 days + 1);

        // Execute inheritance
        vm.prank(executor1);
        bequeath.executeInheritance(owner);

        // Check that assets were distributed
        assertEq(bequeath.getETHBalance(owner), 0);
        assertEq(bequeath.getERC20Balance(owner, address(token)), 0);

        // Check beneficiary balances (60% to beneficiary1, 40% to beneficiary2)
        assertEq(beneficiary1.balance, 1 ether + 6 ether); // 1 ether initial + 6 ether from inheritance
        assertEq(beneficiary2.balance, 1 ether + 4 ether); // 1 ether initial + 4 ether from inheritance

        assertEq(token.balanceOf(beneficiary1), 300 ether); // 60% of 500
        assertEq(token.balanceOf(beneficiary2), 200 ether); // 40% of 500
    }

    function testRevokeWill() public {
        _createBasicWill();

        vm.prank(owner);
        bequeath.revokeWill();

        Bequeath.Will memory will = bequeath.getWill(owner);
        assertEq(uint256(will.status), uint256(Bequeath.WillStatus.Revoked));
    }

    function testCannotExecuteWithoutConsensus() public {
        _createBasicWill();
        _depositTestAssets();

        vm.prank(executor1);
        bequeath.announceInheritance(owner);

        // Only one executor provides consensus (need minimum 2)
        vm.prank(executor1);
        bequeath.provideConsensus(owner);

        vm.warp(block.timestamp + 7 days + 3 days + 1);

        vm.expectRevert("Insufficient executor consensus");
        vm.prank(executor1);
        bequeath.executeInheritance(owner);
    }

    function testCannotExecuteBeforeMoratorium() public {
        _createBasicWill();
        _depositTestAssets();

        vm.prank(executor1);
        bequeath.announceInheritance(owner);

        vm.prank(executor1);
        bequeath.provideConsensus(owner);
        vm.prank(executor2);
        bequeath.provideConsensus(owner);

        // Try to execute before moratorium period
        vm.warp(block.timestamp + 3 days + 1); // Only challenge period passed

        vm.expectRevert("Moratorium period not met");
        vm.prank(executor1);
        bequeath.executeInheritance(owner);
    }

    function testIsExecutor() public {
        _createBasicWill();

        assertTrue(bequeath.isExecutor(owner, executor1));
        assertTrue(bequeath.isExecutor(owner, executor2));
        assertFalse(bequeath.isExecutor(owner, beneficiary1));
        assertFalse(bequeath.isExecutor(owner, nonParticipant));
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
