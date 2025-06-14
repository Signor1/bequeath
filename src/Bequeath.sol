//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IDeathOracle} from "./interface/IDeathOracle.sol";
import {IPUSHCommInterface} from "./interface/IPushNotification.sol";

/**
 * @title Enhanced Bequeathable Asset Registry With Custody
 * @dev Comprehensive inheritance system supporting multiple asset types and enhanced security
 * @author Enhanced from ERC-7878 proposal - https://eips.ethereum.org/EIPS/eip-7878
 */
contract Bequeath is AccessControl, ReentrancyGuard, Pausable, IERC721Receiver, IERC1155Receiver {
    // Use SafeERC20 for safe ERC20 operations
    using SafeERC20 for IERC20;

    // ============ Constants ================
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
        bool isDeposited; // Indicates if the asset is held in custody
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

    // Asset custody tracking
    mapping(address => uint256) public ethBalances; // Track ETH balance per user
    mapping(address => mapping(address => uint256)) public erc20Balances; // user => token => balance
    mapping(address => mapping(address => uint256[])) public erc721Holdings; // user => contract => tokenIds[]
    mapping(address => mapping(address => mapping(uint256 => uint256))) public erc1155Balances; // user => contract => tokenId => amount

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
    event AssetDeposited(address indexed owner, AssetType assetType, address contractAddress, uint256 amount);
    event AssetWithdrawn(address indexed owner, AssetType assetType, address contractAddress, uint256 amount);
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

    modifier onlyOwner(address owner) {
        require(owner == msg.sender, "Only owner");
        _;
    }

    constructor(address _deathOracle, address _pushNotification) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        if (_deathOracle != address(0)) {
            deathOracle = IDeathOracle(_deathOracle);
        }
        if (_pushNotification != address(0)) {
            pushNotification = IPUSHCommInterface(_pushNotification);
        }
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
     * @dev Deposit ETH for inheritance
     */
    function depositETH() external payable whenNotPaused {
        require(wills[msg.sender].owner == msg.sender, "Must have active will");
        require(msg.value > 0, "Must deposit ETH");

        ethBalances[msg.sender] += msg.value;

        // Register or update asset
        _registerOrUpdateAsset(AssetType.ETH, address(0), 0, msg.value, "");

        emit AssetDeposited(msg.sender, AssetType.ETH, address(0), msg.value);
    }

    /**
     * @dev Deposit ERC20 tokens for inheritance
     */
    function depositERC20(address tokenContract, uint256 amount) external whenNotPaused {
        require(wills[msg.sender].owner == msg.sender, "Must have active will");
        require(amount > 0, "Amount must be > 0");

        IERC20(tokenContract).safeTransferFrom(msg.sender, address(this), amount);
        erc20Balances[msg.sender][tokenContract] += amount;

        // Register or update asset
        _registerOrUpdateAsset(AssetType.ERC20, tokenContract, 0, amount, "");

        emit AssetDeposited(msg.sender, AssetType.ERC20, tokenContract, amount);
    }

    /**
     * @dev Deposit ERC721 NFT for inheritance
     */
    function depositERC721(address nftContract, uint256 tokenId) external whenNotPaused {
        require(wills[msg.sender].owner == msg.sender, "Must have active will");

        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);
        erc721Holdings[msg.sender][nftContract].push(tokenId);

        // Register asset
        _registerOrUpdateAsset(AssetType.ERC721, nftContract, tokenId, 1, "");

        emit AssetDeposited(msg.sender, AssetType.ERC721, nftContract, 1);
    }

    /**
     * @dev Deposit ERC1155 tokens for inheritance
     */
    function depositERC1155(address tokenContract, uint256 tokenId, uint256 amount) external whenNotPaused {
        require(wills[msg.sender].owner == msg.sender, "Must have active will");
        require(amount > 0, "Amount must be > 0");

        IERC1155(tokenContract).safeTransferFrom(msg.sender, address(this), tokenId, amount, "");
        erc1155Balances[msg.sender][tokenContract][tokenId] += amount;

        // Register or update asset
        _registerOrUpdateAsset(AssetType.ERC1155, tokenContract, tokenId, amount, "");

        emit AssetDeposited(msg.sender, AssetType.ERC1155, tokenContract, amount);
    }

    /**
     * @dev Withdraw ETH (only owner can withdraw their own assets)
     */
    function withdrawETH(uint256 amount) external nonReentrant onlyOwner(msg.sender) {
        require(ethBalances[msg.sender] >= amount, "Insufficient balance");
        require(
            inheritanceProcesses[msg.sender].status == ProcessStatus.NotStarted,
            "Cannot withdraw during inheritance process"
        );

        ethBalances[msg.sender] -= amount;
        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "Failed to send Ether");

        // Update asset registry
        _updateAssetAmount(AssetType.ETH, address(0), 0, ethBalances[msg.sender]);

        emit AssetWithdrawn(msg.sender, AssetType.ETH, address(0), amount);
    }

    /**
     * @dev Withdraw ERC20 tokens
     */
    function withdrawERC20(address tokenContract, uint256 amount) external nonReentrant onlyOwner(msg.sender) {
        require(erc20Balances[msg.sender][tokenContract] >= amount, "Insufficient balance");
        require(
            inheritanceProcesses[msg.sender].status == ProcessStatus.NotStarted,
            "Cannot withdraw during inheritance process"
        );

        erc20Balances[msg.sender][tokenContract] -= amount;
        IERC20(tokenContract).safeTransfer(msg.sender, amount);

        // Update asset registry
        _updateAssetAmount(AssetType.ERC20, tokenContract, 0, erc20Balances[msg.sender][tokenContract]);

        emit AssetWithdrawn(msg.sender, AssetType.ERC20, tokenContract, amount);
    }

    /**
     * @dev Internal function to register or update asset
     */
    function _registerOrUpdateAsset(
        AssetType _assetType,
        address _contractAddress,
        uint256 _tokenId,
        uint256 _amount,
        bytes memory _additionalData
    ) internal {
        Asset[] storage assets = registeredAssets[msg.sender];

        // Check if asset already exists
        for (uint256 i = 0; i < assets.length; i++) {
            if (
                assets[i].assetType == _assetType && assets[i].contractAddress == _contractAddress
                    && assets[i].tokenId == _tokenId
            ) {
                assets[i].amount += _amount;
                assets[i].isDeposited = true;
                return;
            }
        }

        // Add new asset
        Asset memory newAsset = Asset({
            assetType: _assetType,
            contractAddress: _contractAddress,
            tokenId: _tokenId,
            amount: _amount,
            additionalData: _additionalData,
            isDeposited: true
        });

        assets.push(newAsset);
    }

    /**
     * @dev Internal function to update asset amount
     */
    function _updateAssetAmount(AssetType _assetType, address _contractAddress, uint256 _tokenId, uint256 _newAmount)
        internal
    {
        Asset[] storage assets = registeredAssets[msg.sender];

        for (uint256 i = 0; i < assets.length; i++) {
            if (
                assets[i].assetType == _assetType && assets[i].contractAddress == _contractAddress
                    && assets[i].tokenId == _tokenId
            ) {
                assets[i].amount = _newAmount;
                if (_newAmount == 0) {
                    assets[i].isDeposited = false;
                }
                return;
            }
        }
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

        if (will.requiresOracleVerification && address(deathOracle) != address(0)) {
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

        // Transfer ETH
        if (ethBalances[owner] > 0) {
            uint256 totalETH = ethBalances[owner];
            for (uint256 j = 0; j < will.beneficiaries.length; j++) {
                Beneficiary storage beneficiary = will.beneficiaries[j];
                uint256 transferAmount = (totalETH * beneficiary.percentage) / 10000;
                if (transferAmount > 0) {
                    (bool success,) = payable(beneficiary.beneficiaryAddress).call{value: transferAmount}("");
                    require(success, "Failed to send Ether");
                }
            }
            ethBalances[owner] = 0;
        }

        // Transfer ERC20 tokens
        Asset[] storage assets = registeredAssets[owner];
        for (uint256 i = 0; i < assets.length; i++) {
            Asset storage asset = assets[i];

            if (!asset.isDeposited) continue;

            if (asset.assetType == AssetType.ERC20) {
                uint256 totalAmount = erc20Balances[owner][asset.contractAddress];
                if (totalAmount > 0) {
                    for (uint256 j = 0; j < will.beneficiaries.length; j++) {
                        Beneficiary storage beneficiary = will.beneficiaries[j];
                        uint256 transferAmount = (totalAmount * beneficiary.percentage) / 10000;
                        if (transferAmount > 0) {
                            IERC20(asset.contractAddress).safeTransfer(beneficiary.beneficiaryAddress, transferAmount);
                        }
                    }
                    erc20Balances[owner][asset.contractAddress] = 0;
                }
            } else if (asset.assetType == AssetType.ERC721) {
                // Transfer NFTs to beneficiaries in order
                uint256[] storage tokenIds = erc721Holdings[owner][asset.contractAddress];
                uint256 beneficiaryIndex = 0;

                for (uint256 k = 0; k < tokenIds.length; k++) {
                    if (beneficiaryIndex >= will.beneficiaries.length) {
                        beneficiaryIndex = 0; // Round robin distribution
                    }
                    IERC721(asset.contractAddress).safeTransferFrom(
                        address(this), will.beneficiaries[beneficiaryIndex].beneficiaryAddress, tokenIds[k]
                    );
                    beneficiaryIndex++;
                }
                delete erc721Holdings[owner][asset.contractAddress];
            } else if (asset.assetType == AssetType.ERC1155) {
                uint256 totalAmount = erc1155Balances[owner][asset.contractAddress][asset.tokenId];
                if (totalAmount > 0) {
                    for (uint256 j = 0; j < will.beneficiaries.length; j++) {
                        Beneficiary storage beneficiary = will.beneficiaries[j];
                        uint256 transferAmount = (totalAmount * beneficiary.percentage) / 10000;
                        if (transferAmount > 0) {
                            IERC1155(asset.contractAddress).safeTransferFrom(
                                address(this), beneficiary.beneficiaryAddress, asset.tokenId, transferAmount, ""
                            );
                        }
                    }
                    erc1155Balances[owner][asset.contractAddress][asset.tokenId] = 0;
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

    function getETHBalance(address owner) external view returns (uint256) {
        return ethBalances[owner];
    }

    function getERC20Balance(address owner, address token) external view returns (uint256) {
        return erc20Balances[owner][token];
    }

    function getERC721Holdings(address owner, address nftContract) external view returns (uint256[] memory) {
        return erc721Holdings[owner][nftContract];
    }

    function getERC1155Balance(address owner, address tokenContract, uint256 tokenId) external view returns (uint256) {
        return erc1155Balances[owner][tokenContract][tokenId];
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

    // Required for receiving NFTs
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControl, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC721Receiver).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId
            || super.supportsInterface(interfaceId);
    }

    // Fallback to receive ETH
    receive() external payable {
        // ETH sent directly to contract is not attributed to any user
        // Users must use depositETH() function
        revert("Use depositETH() function");
    }
}
