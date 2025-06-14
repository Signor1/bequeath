# Enhanced Bequeathable Asset Registry (Bequeath)

## 🏛️ Overview

The Bequeath contract is an enhanced implementation of the [ERC-7878](https://eips.ethereum.org/EIPS/eip-7878) proposal, developed by ScanSan Properties to enable secure, automated transfer of digital assets after a person's death. This contract addresses the critical need for digital inheritance in the blockchain ecosystem, supporting multiple asset types including ETH, ERC20 tokens, NFTs (ERC721), and multi-token standards (ERC1155).

## 🚀 Key Features

### Multi-Asset Support

- **ETH**: Native cryptocurrency transfers
- **ERC20**: Fungible token distributions
- **ERC721**: Non-fungible token inheritance
- **ERC1155**: Multi-token standard support

### Advanced Security Mechanisms

- **Multi-Executor System**: Requires consensus from multiple trusted parties
- **Challenge Period**: Built-in dispute resolution mechanism
- **Moratorium Period**: Configurable waiting period (7-365 days)
- **Oracle Integration Ready**: Prepared for future death verification oracles
- **Push Protocol Integration**: Real-time notifications to stakeholders

### Governance & Safety

- **Role-Based Access Control**: Admin and Oracle roles
- **Emergency Pause**: Circuit breaker for critical situations
- **Reentrancy Protection**: Prevents recursive call attacks
- **Comprehensive Event Logging**: Full audit trail

## 📋 Contract Architecture

```bash
Bequeath Contract
├── Will Management
│   ├── Create/Update Will
│   ├── Executor Management
│   └── Beneficiary Distribution
├── Asset Registration
│   ├── ETH Deposits
│   ├── Token Approvals
│   └── NFT Custody
├── Inheritance Process
│   ├── Announcement Phase
│   ├── Challenge Period
│   └── Execution Phase
└── Security & Notifications
    ├── Oracle Verification
    ├── Push Notifications
    └── Emergency Controls
```

## 🔧 Installation & Setup

### Prerequisites

- Solidity ^0.8.19
- OpenZeppelin Contracts
- Push Protocol Integration
- Death Oracle Interface (optional)

### Dependencies

```bash
forge install openzeppelin/openzeppelin-contracts@v5.0.0 --no-commit
```

### Deployment Parameters

```solidity
constructor(
    address _deathOracle,    // Death oracle contract address
    address _pushNotification // Push protocol address
)
```

## 📊 Usage Examples

### Creating a Will

```solidity
address[] memory executors = [0x..., 0x...]; // At least 2 executors
Beneficiary[] memory beneficiaries = [
    Beneficiary(0x..., 5000, "Spouse - 50%"),
    Beneficiary(0x..., 5000, "Child - 50%")
];

bequeath.createWill(
    executors,
    beneficiaries,
    30 days, // moratorium period
    keccak256("identity_hash"),
    false // oracle verification not required
);
```

### Inheritance Process

```solidity
// 1. Executor announces inheritance
bequeath.announceInheritance(deceasedAddress);

// 2. Other executors provide consensus
bequeath.provideConsensus(deceasedAddress);

// 3. Wait for challenge period and moratorium
// 4. Execute inheritance
bequeath.executeInheritance(deceasedAddress);
```

## ⚠️ Real-World Viability Challenges

### 1. Death Verification Oracle Problem

**Current Reality**: No production-ready death verification oracles exist in the blockchain ecosystem.

**Challenges**:

- **Legal Compliance**: Death certificate verification across jurisdictions
- **Privacy Laws**: GDPR, HIPAA, and other privacy regulations
- **Authentication**: Linking blockchain addresses to real-world identities
- **Liability**: Oracle providers face massive liability for incorrect determinations
- **Timeliness**: Official death records can take weeks to process

**Current Solution**: Multi-executor consensus with time-based triggers (inactivity periods)

### 2. Legal & Regulatory Challenges

#### Jurisdictional Issues

- Digital asset inheritance laws vary by country/state
- Smart contracts may not be legally recognized as valid wills
- Cross-border inheritance complications
- Tax implications for beneficiaries

#### Compliance Requirements

- KYC/AML requirements for asset transfers
- Estate tax obligations
- Legal executor requirements
- Court probate process integration

### 3. Technical Challenges

#### Asset Custody Risks

- Smart contract bugs could lock assets permanently
- Upgrade mechanisms vs. immutability
- Gas costs for complex distributions
- MEV attacks during inheritance execution

#### Identity Verification

- Linking on-chain addresses to real-world identities
- Preventing identity theft/impersonation
- Executor verification and authorization
- Beneficiary address validation

### 4. Social & Adoption Challenges

#### User Experience

- Complex setup process for non-technical users
- Key management and recovery
- Educational barrier for traditional inheritance concepts
- Trust in smart contract systems

#### Economic Factors

- High gas costs for complex operations
- Asset custody fees
- Oracle service costs
- Limited insurance coverage

## 🛡️ Security Considerations

### Smart Contract Risks

- **Reentrancy Attacks**: Mitigated with ReentrancyGuard
- **Integer Overflow**: Prevented by Solidity ^0.8.0
- **Access Control**: Role-based permissions with OpenZeppelin
- **Emergency Stops**: Pausable functionality for critical issues

### Operational Risks

- **Executor Collusion**: Requires minimum consensus threshold
- **False Death Claims**: Challenge period and dispute resolution
- **Asset Recovery**: Emergency functions for stuck assets
- **Oracle Failures**: Fallback to time-based mechanisms

### Recommended Security Practices

1. **Multi-signature wallets** for admin functions
2. **Time locks** for critical parameter changes
3. **Regular security audits** by reputable firms
4. **Bug bounty programs** for ongoing security testing
5. **Insurance coverage** for smart contract risks

## 🔮 Future Roadmap

### Phase 1: Core Functionality (Current)

- ✅ Multi-asset inheritance system
- ✅ Multi-executor consensus mechanism
- ✅ Push Protocol notifications
- ✅ Challenge and dispute resolution

### Phase 2: Enhanced Oracle Integration

- 🔄 Professional death verification network
- 🔄 Government API integrations
- 🔄 Multi-source consensus oracles
- 🔄 Chainlink External Adapter development

### Phase 3: Legal Integration

- 📋 Legal framework partnerships
- 📋 Jurisdiction-specific implementations
- 📋 Traditional estate planning integration
- 📋 Tax optimization features

### Phase 4: Mainstream Adoption

- 📋 User-friendly interfaces
- 📋 Mobile applications
- 📋 Integration with existing wallet providers
- 📋 Educational content and certification

## 🤝 Contributing

We welcome contributions from the crypto community! Please review our contributing guidelines and submit pull requests for:

- Security improvements
- Gas optimization
- Oracle integrations
- Legal compliance features
- Documentation enhancements

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚡ Quick Start

1. **Clone the repository**
2. **Install dependencies**: `forge install`
3. **Compile contracts**: `forge build`
4. **Run tests**: `forge test`
5. **Deploy**: `forge script script/Bequeath.s.sol:Bequeath --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast`

---

**⚠️ Disclaimer**: This smart contract system is experimental and should not be used for significant asset amounts without proper legal consultation and comprehensive security auditing. Digital inheritance involves complex legal considerations that vary by jurisdiction. Always consult with qualified legal and tax professionals before implementing any inheritance strategy.
