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
import {IPUSHCommInterface} from "./interface/IPushNotification.sol";

/**
 * @title Enhanced Bequeathable Asset Registry
 * @dev Comprehensive inheritance system supporting multiple asset types and enhanced security
 * @author Enhanced from ERC-7878 proposal - https://eips.ethereum.org/EIPS/eip-7878
 */
contract Bequeath is AccessControl, ReentrancyGuard, Pausable {
    // Roles
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ============ Structs ================

    // Enhanced Will structure
    struct Will {
        address owner;
        address[] executors;
        Beneficiary[] beneficiaries;
        uint256 moratoriumPeriod;
        uint256 createdAt;
        uint256 lastUpdated;
        bytes32 identityHash; // For death oracle verification
        bool requiresOracleVerification;
        WillStatus status;
    }

    struct Beneficiary {
        address beneficiaryAddress;
        uint256 percentage; // Basis points (1% = 100)
        string description;
    }

    struct Asset {
        AssetType assetType;
        address contractAddress;
        uint256 tokenId; // For ERC721/ERC1155
        uint256 amount; // For ERC20/ERC1155/ETH
        bytes additionalData;
    }

    // Inheritance process structure
    struct InheritanceProcess {
        address initiator;
        uint256 startTime;
        uint256 challengeEndTime;
        bool oracleVerified;
        ProcessStatus status;
        address[] challengers;
        uint256 executorConsensusCount;
    }

    // ============== Enums ============
    enum AssetType {
        None,
        ETH,
        ERC20,
        ERC721,
        ERC1155
    }

    enum WillStatus {
        None,
        Active,
        Suspended,
        Executed,
        Revoked
    }

    enum ProcessStatus {
        NotStarted,
        Announced,
        Challenged,
        ReadyForExecution,
        Executed,
        Cancelled
    }

    // State variables
    mapping(address => Will) public wills;
    mapping(address => Asset[]) public registeredAssets;
    mapping(address => InheritanceProcess) public inheritanceProcesses;
    mapping(address => mapping(address => bool)) public executorConsensus;

    // Death oracle and push notification interfaces
    IDeathOracle public deathOracle;
    IPUSHCommInterface public pushNotification;

    // Constants
    uint256 public constant MIN_MORATORIUM_PERIOD = 7 days;
    uint256 public constant MAX_MORATORIUM_PERIOD = 365 days;
    uint256 public constant CHALLENGE_PERIOD = 3 days;
    uint256 public constant MIN_EXECUTOR_CONSENSUS = 2; // Minimum executors needed for consensus

    // Events
    event WillCreated(address indexed owner, uint256 executorCount, uint256 beneficiaryCount);
    event WillUpdated(address indexed owner, uint256 timestamp);
    event AssetRegistered(address indexed owner, AssetType assetType, address contractAddress);
    event InheritanceAnnounced(address indexed owner, address indexed initiator, uint256 challengeDeadline);
    event InheritanceChallenged(address indexed owner, address indexed challenger);
    event InheritanceExecuted(address indexed owner, uint256 totalBeneficiaries);
    event OracleVerificationRequested(address indexed owner, bytes32 identityHash);
    event NotificationSent(address indexed recipient, string title);

    // Modifiers
    modifier onlyOwnerOrExecutor(address owner) {
        require(owner == msg.sender || isExecutor(owner, msg.sender), "Only owner or executor");
        _;
    }

    modifier onlyValidWill(address owner) {
        require(wills[owner].owner == owner, "Will does not exist");
        require(wills[owner].status == WillStatus.Active, "Will not active");
        _;
    }

    constructor(address _deathOracle, address _pushNotification) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        deathOracle = IDeathOracle(_deathOracle);
        pushNotification = IPUSHCommInterface(_pushNotification);
    }

    /**
     * @dev Create or update a will with multiple executors and beneficiaries
     * @param _executors Array of executor addresses
     * @param _beneficiaries Array of beneficiary structs
     * @param _moratoriumPeriod Moratorium period in seconds
     * @param _identityHash Hash of the owner's identity for oracle verification
     * @param _requiresOracleVerification Whether oracle verification is required
     */
    function createWill(
        address[] calldata _executors,
        Beneficiary[] calldata _beneficiaries,
        uint256 _moratoriumPeriod,
        bytes32 _identityHash,
        bool _requiresOracleVerification
    ) external whenNotPaused {
        require(_executors.length >= 2, "Minimum 2 executors required");
        require(_executors.length <= 10, "Maximum 10 executors allowed");
        require(_beneficiaries.length > 0, "At least one beneficiary required");
        require(_beneficiaries.length <= 20, "Maximum 20 beneficiaries allowed");
        require(
            _moratoriumPeriod >= MIN_MORATORIUM_PERIOD && _moratoriumPeriod <= MAX_MORATORIUM_PERIOD,
            "Invalid moratorium period"
        );

        // Validate beneficiary percentages sum to 100%
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            require(_beneficiaries[i].beneficiaryAddress != address(0), "Invalid beneficiary address");
            require(_beneficiaries[i].percentage > 0, "Beneficiary percentage must be > 0");
            totalPercentage += _beneficiaries[i].percentage;
        }
        require(totalPercentage == 10000, "Beneficiary percentages must sum to 100%");

        // Validate executors
        for (uint256 i = 0; i < _executors.length; i++) {
            require(_executors[i] != address(0), "Invalid executor address");
            require(_executors[i] != msg.sender, "Owner cannot be executor");
        }

        Will storage will = wills[msg.sender];
        bool isUpdate = will.owner == msg.sender;

        will.owner = msg.sender;
        will.executors = _executors;
        delete will.beneficiaries; // Clear existing beneficiaries
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            will.beneficiaries.push(_beneficiaries[i]);
        }
        will.moratoriumPeriod = _moratoriumPeriod;
        will.identityHash = _identityHash;
        will.requiresOracleVerification = _requiresOracleVerification;
        will.status = WillStatus.Active;
        will.lastUpdated = block.timestamp;

        if (!isUpdate) {
            will.createdAt = block.timestamp;
            emit WillCreated(msg.sender, _executors.length, _beneficiaries.length);
        } else {
            emit WillUpdated(msg.sender, block.timestamp);
        }

        // Send notifications to executors
        _notifyExecutors(msg.sender, isUpdate ? "Will Updated" : "Will Created");
    }

    /**
     * @dev Register an asset for inheritance
     * @param _assetType Type of the asset (ETH, ERC20, ERC721, ERC1155)
     * @param _contractAddress Address of the asset contract (if applicable)
     * @param _tokenId Token ID for NFTs (0 for ETH/ERC20)
     * @param _amount Amount of the asset (0 for NFTs)
     * @param _additionalData Additional data for the asset (if needed)
     */
    function registerAsset(
        AssetType _assetType,
        address _contractAddress,
        uint256 _tokenId,
        uint256 _amount,
        bytes calldata _additionalData
    ) external whenNotPaused {
        require(wills[msg.sender].owner == msg.sender, "Must have active will");

        Asset memory newAsset = Asset({
            assetType: _assetType,
            contractAddress: _contractAddress,
            tokenId: _tokenId,
            amount: _amount,
            additionalData: _additionalData
        });

        registeredAssets[msg.sender].push(newAsset);
        emit AssetRegistered(msg.sender, _assetType, _contractAddress);
    }

    /**
     * @dev Announce inheritance process
     * @param owner Address of the will owner
     */
    function announceInheritance(address owner) external whenNotPaused onlyValidWill(owner) nonReentrant {
        require(isExecutor(owner, msg.sender), "Only executor can announce");
        require(inheritanceProcesses[owner].status == ProcessStatus.NotStarted, "Process already started");

        Will storage will = wills[owner];

        // If oracle verification required, check death status
        if (will.requiresOracleVerification) {
            (bool verified,) = deathOracle.isPersonDeceased(will.identityHash);
            if (!verified) {
                // Request verification if not already verified
                deathOracle.requestDeathVerification(will.identityHash, "");
                emit OracleVerificationRequested(owner, will.identityHash);
                revert("Oracle verification pending");
            }
        }

        InheritanceProcess storage process = inheritanceProcesses[owner];
        process.initiator = msg.sender;
        process.startTime = block.timestamp;
        process.challengeEndTime = block.timestamp + CHALLENGE_PERIOD;
        process.status = ProcessStatus.Announced;

        if (will.requiresOracleVerification) {
            (bool verified,) = deathOracle.isPersonDeceased(will.identityHash);
            process.oracleVerified = verified;
        } else {
            process.oracleVerified = true; // Skip oracle for non-oracle wills
        }

        emit InheritanceAnnounced(owner, msg.sender, process.challengeEndTime);

        // Send notifications
        _notifyBeneficiaries(owner, "Inheritance Process Started");
        _notifyExecutors(owner, "Inheritance Announced");
    }

    /**
     * @dev Provide consensus for inheritance process
     * @param owner Address of the will owner
     */
    function provideConsensus(address owner) external onlyValidWill(owner) {
        require(isExecutor(owner, msg.sender), "Only executor can provide consensus");
        require(inheritanceProcesses[owner].status == ProcessStatus.Announced, "Invalid process status");
        require(!executorConsensus[owner][msg.sender], "Consensus already provided");

        executorConsensus[owner][msg.sender] = true;
        inheritanceProcesses[owner].executorConsensusCount++;
    }

    /**
     * @dev Challenge inheritance process
     * @param owner Address of the will owner
     * @param reason Reason for challenging
     */
    function challengeInheritance(address owner, string calldata reason) external onlyOwnerOrExecutor(owner) {
        InheritanceProcess storage process = inheritanceProcesses[owner];
        require(process.status == ProcessStatus.Announced, "Cannot challenge at this stage");
        require(block.timestamp <= process.challengeEndTime, "Challenge period expired");

        process.status = ProcessStatus.Challenged;
        process.challengers.push(msg.sender);

        emit InheritanceChallenged(owner, msg.sender);
        _notifyExecutors(owner, string(abi.encodePacked("Inheritance Challenged: ", reason)));
    }

    /**
     * @dev Execute inheritance process after moratorium and challenge period
     * @param owner Address of the will owner
     */
    function executeInheritance(address owner) external whenNotPaused onlyValidWill(owner) nonReentrant {
        require(isExecutor(owner, msg.sender), "Only executor can execute");

        InheritanceProcess storage process = inheritanceProcesses[owner];
        Will storage will = wills[owner];

        require(process.status == ProcessStatus.Announced, "Invalid process status");
        require(block.timestamp > process.challengeEndTime, "Challenge period not expired");
        require(block.timestamp >= process.startTime + will.moratoriumPeriod, "Moratorium period not met");
        require(process.executorConsensusCount >= MIN_EXECUTOR_CONSENSUS, "Insufficient executor consensus");

        if (will.requiresOracleVerification) {
            require(process.oracleVerified, "Oracle verification required");
        }

        process.status = ProcessStatus.Executed;
        will.status = WillStatus.Executed;

        // Execute asset transfers
        _transferAssets(owner);

        emit InheritanceExecuted(owner, will.beneficiaries.length);
        _notifyBeneficiaries(owner, "Inheritance Executed Successfully");
    }

    /**
     * @dev Transfer assets to beneficiaries
     * @param owner Address of the will owner
     */
    function _transferAssets(address owner) internal {
        Will storage will = wills[owner];
        Asset[] storage assets = registeredAssets[owner];

        for (uint256 i = 0; i < assets.length; i++) {
            Asset storage asset = assets[i];

            for (uint256 j = 0; j < will.beneficiaries.length; j++) {
                Beneficiary storage beneficiary = will.beneficiaries[j];
                uint256 transferAmount = (asset.amount * beneficiary.percentage) / 10000;

                if (transferAmount == 0) continue;

                if (asset.assetType == AssetType.ETH) {
                    payable(beneficiary.beneficiaryAddress).transfer(transferAmount);
                } else if (asset.assetType == AssetType.ERC20) {
                    IERC20(asset.contractAddress).transferFrom(owner, beneficiary.beneficiaryAddress, transferAmount);
                } else if (asset.assetType == AssetType.ERC721) {
                    // For NFTs, transfer to beneficiary with highest percentage for this asset
                    if (j == 0) {
                        // Transfer to first beneficiary for simplicity
                        IERC721(asset.contractAddress).transferFrom(
                            owner, beneficiary.beneficiaryAddress, asset.tokenId
                        );
                    }
                } else if (asset.assetType == AssetType.ERC1155) {
                    IERC1155(asset.contractAddress).safeTransferFrom(
                        owner, beneficiary.beneficiaryAddress, asset.tokenId, transferAmount, ""
                    );
                }
            }
        }
    }

    /**
     * @dev Emergency pause and unpause functions
     * @notice Allows admin to pause or unpause the contract
     */
    function emergencyPause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function emergencyUnpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Revoke an existing will
     * @notice Can only be called by the owner of the will
     */
    function revokeWill() external {
        require(wills[msg.sender].owner == msg.sender, "No will exists");
        require(
            inheritanceProcesses[msg.sender].status == ProcessStatus.NotStarted, "Cannot revoke during active process"
        );

        wills[msg.sender].status = WillStatus.Revoked;
        _notifyExecutors(msg.sender, "Will Revoked");
    }

    // ====== View functions =======
    function getWill(address owner) external view returns (Will memory) {
        return wills[owner];
    }

    function getAssets(address owner) external view returns (Asset[] memory) {
        return registeredAssets[owner];
    }

    function getInheritanceProcess(address owner) external view returns (InheritanceProcess memory) {
        return inheritanceProcesses[owner];
    }

    // ======= Helper Functions =========
    /**
     * @dev Check if an address is an executor of a will
     * @param owner Address of the will owner
     * @param executor Address to check
     * @return bool True if the address is an executor, false otherwise
     */
    function isExecutor(address owner, address executor) public view returns (bool) {
        Will storage will = wills[owner];
        for (uint256 i = 0; i < will.executors.length; i++) {
            if (will.executors[i] == executor) return true;
        }
        return false;
    }

    // Internal notification functions
    /**
     * @dev Notify executors and beneficiaries via push notifications
     * @param owner Address of the will owner
     * @param message Notification message
     */
    function _notifyExecutors(address owner, string memory message) internal {
        Will storage will = wills[owner];
        for (uint256 i = 0; i < will.executors.length; i++) {
            try pushNotification.sendNotification(
                address(0x123), // Channel address, replace with actual channel address
                will.executors[i], // Recipient address
                bytes(
                    string(
                        // We are passing identity here: https://comms.push.org/docs/notifications/notification-standards/notification-standards-advance/#notification-identity
                        abi.encodePacked(
                            "0", // this represents minimal identity,
                            "+", // segregator
                            "3", // define notification type: (1, 3 or 4) = (Broadcast, targeted or subset)
                            "+", // segregator
                            "Inheritance Update", // this is notification title
                            "+", // segregator
                            "Body" // notification body
                        )
                    )
                )
            ) {
                emit NotificationSent(will.executors[i], message);
            } catch {
                // Continue if notification fails
            }
        }
    }

    /**
     * @dev Notify beneficiaries via push notifications
     * @param owner Address of the will owner
     * @param message Notification message
     */
    function _notifyBeneficiaries(address owner, string memory message) internal {
        Will storage will = wills[owner];
        for (uint256 i = 0; i < will.beneficiaries.length; i++) {
            try pushNotification.sendNotification(
                address(0x123), // Channel address, replace with actual channel address
                will.beneficiaries[i].beneficiaryAddress,
                bytes(
                    string(
                        // We are passing identity here: https://comms.push.org/docs/notifications/notification-standards/notification-standards-advance/#notification-identity
                        abi.encodePacked(
                            "0", // this represents minimal identity,
                            "+", // segregator
                            "3", // define notification type: (1, 3 or 4) = (Broadcast, targeted or subset)
                            "+", // segregator
                            "Inheritance Update", // this is notification title
                            "+", // segregator
                            "Body" // notification body
                        )
                    )
                )
            ) {
                emit NotificationSent(will.beneficiaries[i].beneficiaryAddress, message);
            } catch {
                // Continue if notification fails
            }
        }
    }

    // Oracle integration
    function updateDeathOracle(address newOracle) external onlyRole(ADMIN_ROLE) {
        deathOracle = IDeathOracle(newOracle);
    }

    // Fallback to receive ETH
    receive() external payable {}
}
