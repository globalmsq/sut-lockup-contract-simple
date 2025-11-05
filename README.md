# SimpleLockup - Minimal Token Vesting Contract

A simplified, production-ready smart contract for SUT token lockup with linear vesting on Polygon. **One lockup per address** - maximum simplicity.

## Key Features

- ✅ **One lockup per address** - No complexity, no arrays, no enumeration
- ✅ **Linear vesting** with cliff period support
- ✅ **Revocable lockups** - Owner can revoke unvested tokens
- ✅ **Immutable token address** - Set once at deployment
- ✅ **No pause mechanism** - Reduced attack surface
- ✅ **Optimized & simplified** - Minimal code complexity, lower gas costs

## Removed Features (from original TokenLockup)

- ❌ Multiple lockups per contract
- ❌ Emergency withdrawal system
- ❌ Lockup deletion
- ❌ Token address changes
- ❌ Pause/unpause functionality
- ❌ Pagination and enumeration

## Contract Architecture

```
SimpleLockup
├── mapping(address => LockupInfo) public lockups  // One lockup per address
├── IERC20 public immutable token                  // Set at deployment
└── 7 core functions (vs 22 in original)
```

### Core Functions

1. `createLockup()` - Create lockup for beneficiary (owner only)
2. `release()` - Claim vested tokens (beneficiary)
3. `revoke()` - Revoke unvested tokens (owner only)
4. `vestedAmount()` - Get vested token amount
5. `releasableAmount()` - Get claimable token amount
6. `getVestingProgress()` - Get vesting percentage (0-100)
7. `getRemainingVestingTime()` - Get remaining vesting time in seconds

## Quick Start

### Prerequisites

- Node.js >= 20
- pnpm >= 8
- Docker (for integration tests)

### Installation

```bash
# Clone the repository
git clone <your-repo-url>
cd sut-lockup-contract-simple

# Install dependencies
pnpm install

# Compile contracts
pnpm build
```

### Configuration

Create `.env` file:

```bash
cp .env.example .env
```

Required variables:

```env
PRIVATE_KEY=your_private_key_here
TOKEN_ADDRESS=sut_token_address
POLYGON_RPC_URL=https://polygon-rpc.com
AMOY_RPC_URL=https://rpc-amoy.polygon.technology
ETHERSCAN_API_KEY=your_etherscan_api_key
```

### Testing

```bash
# Run unit tests
pnpm test

# Run with coverage
pnpm test:coverage

# Run integration tests (Docker required)
pnpm integration-tests
```

## Deployment

### Testnet (Amoy)

```bash
# Set environment variables
export PRIVATE_KEY=0x...
export TOKEN_ADDRESS=0xE4C687167705Abf55d709395f92e254bdF5825a2  # Amoy testnet SUT

# Deploy
pnpm deploy:testnet

# Verify
pnpm verify:testnet
```

### Mainnet (Polygon)

```bash
# Set environment variables
export PRIVATE_KEY=0x...
export TOKEN_ADDRESS=0x98965474EcBeC2F532F1f780ee37b0b05F77Ca55  # Polygon mainnet SUT

# Deploy
pnpm deploy:mainnet

# Verify
pnpm verify:mainnet
```

## Usage Examples

### Create a Lockup (Interactive)

```bash
export LOCKUP_ADDRESS=0x...
pnpm create-lockup
```

### Check Lockup Status

```bash
export LOCKUP_ADDRESS=0x...
export BENEFICIARY_ADDRESS=0x...
pnpm check-lockup
```

### Release Vested Tokens

```bash
export LOCKUP_ADDRESS=0x...
pnpm release-helper
```

### Revoke Lockup (Owner)

```bash
export LOCKUP_ADDRESS=0x...
pnpm revoke-helper
```

### Calculate Vesting Timeline

```bash
export LOCKUP_ADDRESS=0x...
export BENEFICIARY_ADDRESS=0x...
pnpm calculate-vested
```

## Smart Contract Details

### Deployment

```solidity
constructor(address _token)
```

- Validates token address (must be a contract, not EOA)
- Sets immutable token address
- Owner set to deployer
- ⚠️ **Deployer must verify ERC20 compatibility before deployment**

### Create Lockup

```solidity
function createLockup(
    address beneficiary,
    uint256 amount,
    uint256 cliffDuration,
    uint256 vestingDuration,
    bool revocable
) external onlyOwner
```

**Requirements:**

- Only one lockup per beneficiary
- Beneficiary cannot be zero address or contract itself
- Amount must be > 0
- Vesting duration must be > 0
- Cliff duration ≤ vesting duration
- Vesting duration ≤ 10 years (MAX_VESTING_DURATION)

### Release Tokens

```solidity
function release() external
```

- Beneficiary claims vested tokens
- Reverts if no tokens available
- At vesting end, releases ALL remaining tokens (eliminates rounding dust)

### Revoke Lockup

```solidity
function revoke(address beneficiary) external onlyOwner
```

- Only revocable lockups can be revoked
- Freezes vesting at current amount
- Returns unvested tokens to owner
- Beneficiary keeps already vested tokens

## Important Behaviors

### Vesting Precision

The contract uses integer division for gas efficiency. Key characteristics:

- **Rounding**: Each calculation has < 1 token rounding error (Solidity integer division)
- **No Cumulative Error**: Each vesting calculation is independent, not incremental
- **Auto-correction**: Errors self-correct in subsequent releases
- **Example (50,000,000 tokens, 10 years)**:
  - Day 1: vested = 13,698 tokens (actual: 13,698.63)
    - Release: 13,698 tokens
  - Day 2: vested = 27,397 tokens (actual: 27,397.26)
    - Release: 27,397 - 13,698 = 13,699 tokens (error corrected!)
  - Day 3+: Continues with independent calculations
  - Last day: All remaining tokens released (zero final loss)
- **Revocation precision**: < 1 token loss at revoke (e.g., 0.000002% for 50M tokens)
- **Completion**: All remaining tokens released at vesting end (eliminates rounding dust)

### Revocation Behavior

When a lockup is revoked, the following behavior is **intentional and by design**:

- **Beneficiary Rights**: Keeps all tokens vested at the time of revocation
- **Future Vesting Only**: Revocation stops future vesting, does not confiscate vested tokens
- **Fair Usage**: If beneficiary calls `release()` before owner calls `revoke()`, this is acceptable
- **Not a Vulnerability**: "Front-running" revoke with release() is fair usage, not an attack
- **Design Rationale**: Revocation punishes future benefits, not past work

**Example Timeline**:
```
T=0:       Lockup created (1000 tokens, 1 year vesting)
T=6mo:     500 tokens vested, beneficiary hasn't claimed yet
T=6mo+1s:  Owner submits revoke() transaction (pending in mempool)
T=6mo+1s:  Beneficiary sees pending revoke, calls release()
Result:    Beneficiary receives 500 tokens, owner receives 500 tokens back
Status:    Fair and intended - beneficiary earned those tokens over 6 months
```

## Security

- **ReentrancyGuard**: Protection against reentrancy attacks
- **SafeERC20**: Safe token transfers
- **Ownable**: Access control for admin functions
- **No pause mechanism**: Reduced attack surface
- **Immutable token**: Cannot be changed after deployment
- **Simplified validation**: Reduced code complexity, easier to audit

### Important Security Notes

⚠️ **Deployer Responsibilities:**

- Verify token address is correct ERC20 contract
- Ensure token doesn't implement ERC-777 hooks
- Test on testnet before mainnet deployment

⚠️ This contract should undergo independent security audit before mainnet deployment.

## Gas Optimization

| Operation    | Gas Cost (approx) |
| ------------ | ----------------- |
| createLockup | ~120,000          |
| release      | ~50,000           |
| revoke       | ~55,000           |

## Docker Integration Tests

Run full test suite with Docker:

```bash
pnpm integration-tests
```

This will:

1. Start local Hardhat node
2. Deploy test contracts
3. Run unit tests
4. Run integration tests
5. Clean up

## Available Scripts

### Build & Test

- `pnpm build` - Compile contracts
- `pnpm test` - Run unit tests
- `pnpm test:coverage` - Generate coverage report
- `pnpm test:integration` - Run integration tests
- `pnpm integration-tests` - Full Docker test suite

### Deployment

- `pnpm deploy:mainnet` - Deploy to Polygon mainnet
- `pnpm deploy:testnet` - Deploy to Amoy testnet
- `pnpm deploy:local` - Deploy to local network

### Utilities

- `pnpm check-lockup` - Check lockup status
- `pnpm calculate-vested` - Calculate vesting timeline
- `pnpm create-lockup` - Interactive lockup creation
- `pnpm debug-lockup` - Debug lockup issues
- `pnpm list-lockups` - Show contract info

### Code Quality

- `pnpm lint` - Run ESLint
- `pnpm lint:fix` - Fix linting issues
- `pnpm format` - Format code with Prettier

## License

MIT

## Support

For issues or questions, please open a GitHub issue.
