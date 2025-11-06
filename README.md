# SimpleLockup - Minimal Token Vesting Contract

A simplified, production-ready smart contract for ERC20 token lockup with linear vesting on Polygon. **One lockup per contract** - maximum simplicity.

## Key Features

- ✅ **One lockup per contract** - Single beneficiary design, no mapping complexity
- ✅ **Linear vesting** with cliff period support
- ✅ **Revocable lockups** - Owner can revoke unvested tokens
- ✅ **Immutable token address** - Set once at deployment
- ✅ **No pause mechanism** - Reduced attack surface
- ✅ **Optimized & simplified** - Minimal code complexity, lower gas costs

## ⚠️ Token Compatibility & Security

### Compatible Tokens

✅ **Standard ERC-20 tokens**
✅ **Tokens without transfer fees**
✅ **Tokens with fixed supply** (non-rebasing)

### Incompatible Tokens

❌ **ERC-777 tokens** - Reentrancy risk via `tokensReceived`/`tokensToSend` hooks
❌ **Deflationary tokens** - Transfer fees cause balance mismatch (auto-detected and rejected)
❌ **Rebasing tokens** - Automatic balance changes (e.g., stETH, aTokens)

The contract automatically validates the received token amount during lockup creation and will reject deflationary tokens.

### Security Features

🛡️ **Overflow Protection** - Uses `Math.mulDiv` for safe large number calculations
🛡️ **Balance Validation** - Verifies actual received amount matches expected amount
🛡️ **Reentrancy Guards** - Protected by OpenZeppelin's `ReentrancyGuard`
🛡️ **Optimized Validations** - Gas-efficient validation order (SLOAD checks first)

### Security Considerations

**Revoke Front-Running**

- Revoke transactions are visible in the mempool
- Beneficiaries can call `release()` before revoke executes
- This is **intended behavior** - vested tokens belong to beneficiary
- For sensitive revocations, consider using private transactions (e.g., Flashbots)

**Cliff Period Behavior**

- `cliff == vesting` is now **prohibited** to ensure gradual vesting
- If you need a simple time-lock, use a separate time-lock contract
- During cliff period, revoke returns 100% of tokens to owner

**Best Practices**

- ✅ Use standard ERC-20 tokens only
- ✅ Test with small amounts first
- ✅ Verify token contract before deployment
- ✅ Use multi-sig wallets for beneficiary addresses
- ✅ Monitor revoke transactions for sensitive lockups

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
├── LockupInfo private lockupInfo    // Single lockup storage
├── address public beneficiary        // Single beneficiary
├── IERC20 public immutable token     // Set at deployment
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
cd erc20-lockup-simple

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
# Deployment (set these before deploying)
PRIVATE_KEY=your_private_key_here
TOKEN_ADDRESS=erc20_token_address

# Network RPC URLs
POLYGON_RPC_URL=https://polygon-rpc.com
AMOY_RPC_URL=https://rpc-amoy.polygon.technology

# Optional (for contract verification)
ETHERSCAN_API_KEY=your_etherscan_api_key

# Note: LOCKUP_ADDRESS is set via export when running helper scripts (after deployment)
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
# Configure .env file with your values:
# PRIVATE_KEY=0x...
# TOKEN_ADDRESS=0xE4C687167705Abf55d709395f92e254bdF5825a2  # Amoy testnet SUT

# Deploy
pnpm deploy:testnet

# Verify
pnpm verify:testnet
```

### Mainnet (Polygon)

```bash
# Configure .env file with your values:
# PRIVATE_KEY=0x...
# TOKEN_ADDRESS=0x98965474EcBeC2F532F1f780ee37b0b05F77Ca55  # Polygon mainnet SUT

# Deploy
pnpm deploy:mainnet

# Verify
pnpm verify:mainnet
```

## Usage Examples

> **Note**: All helper scripts require:
>
> 1. `--network` parameter to specify which network your contract is deployed on:
>    - `--network amoy` for Polygon testnet
>    - `--network polygon` for Polygon mainnet
> 2. `LOCKUP_ADDRESS` environment variable (obtained after deployment):
>    ```bash
>    export LOCKUP_ADDRESS=0x...  # Replace with your deployed contract address
>    ```

### Create a Lockup (Interactive)

```bash
export LOCKUP_ADDRESS=0x...
npx hardhat run scripts/create-lockup-helper.ts --network amoy
# Or for mainnet:
# npx hardhat run scripts/create-lockup-helper.ts --network polygon
```

### Check Lockup Status

```bash
export LOCKUP_ADDRESS=0x...
npx hardhat run scripts/check-lockup.ts --network amoy
```

### Release Vested Tokens

```bash
export LOCKUP_ADDRESS=0x...
npx hardhat run scripts/release-helper.ts --network amoy
```

### Revoke Lockup (Owner)

```bash
export LOCKUP_ADDRESS=0x...
npx hardhat run scripts/revoke-helper.ts --network amoy
```

### Calculate Vesting Timeline

```bash
export LOCKUP_ADDRESS=0x...
npx hardhat run scripts/calculate-vested.ts --network amoy
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

- Only one lockup per contract (single beneficiary design)
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
- Reverts if caller is not the beneficiary
- Reverts if no tokens available
- At vesting end, releases ALL remaining tokens (eliminates rounding dust)

### Revoke Lockup

```solidity
function revoke() external onlyOwner
```

- Only revocable lockups can be revoked
- Freezes vesting at current amount
- Returns unvested tokens to owner
- Beneficiary keeps already vested tokens
- **Cliff Period**: If revoked before cliff ends, all tokens return to owner (0 vested)

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

## Scripts Reference

### Quick Reference

| Script               | Command                                       | Purpose                                     |
| -------------------- | --------------------------------------------- | ------------------------------------------- |
| **Deployment**       |                                               |                                             |
| Production Deploy    | `pnpm deploy:mainnet` / `pnpm deploy:testnet` | Deploy to Polygon networks                  |
| Test Deploy          | `pnpm deploy:local`                           | Deploy with MockERC20 for testing           |
| **Management**       |                                               |                                             |
| Create Lockup        | `pnpm create-lockup`                          | Interactive lockup creation with validation |
| Release Tokens       | `pnpm release-helper`                         | Beneficiary claims vested tokens            |
| Revoke Lockup        | `pnpm revoke-helper`                          | Owner revokes unvested tokens               |
| **Query & Analysis** |                                               |                                             |
| Check Status         | `pnpm check-lockup`                           | View comprehensive lockup information       |
| Calculate Timeline   | `pnpm calculate-vested`                       | Calculate vesting schedule and milestones   |
| List Contract Info   | `pnpm list-lockups`                           | Display contract and token details          |
| **Debugging**        |                                               |                                             |
| Debug Issues         | `pnpm debug-lockup`                           | Diagnose lockup creation problems           |
| **Testing**          |                                               |                                             |
| Unit Tests           | `pnpm test`                                   | Run Hardhat tests                           |
| Integration Tests    | `pnpm integration-tests`                      | Full Docker test suite                      |
| **Code Quality**     |                                               |                                             |
| Lint                 | `pnpm lint` / `pnpm lint:fix`                 | Check/fix code style                        |
| Format               | `pnpm format`                                 | Format with Prettier                        |
| Build                | `pnpm build`                                  | Compile contracts                           |

---

### Deployment Scripts

#### Production Deployment (`deploy.ts`)

Deploy SimpleLockup contract to Polygon mainnet or Amoy testnet.

**Environment Variables:**

- `PRIVATE_KEY` (required) - Deployer's private key
- `TOKEN_ADDRESS` (required) - ERC20 token address
  - Example Polygon Mainnet: `0x98965474EcBeC2F532F1f780ee37b0b05F77Ca55`
  - Example Amoy Testnet: `0xE4C687167705Abf55d709395f92e254bdF5825a2`
- `ETHERSCAN_API_KEY` (optional) - For contract verification

**Usage:**

```bash
# Configure .env with your values (PRIVATE_KEY, TOKEN_ADDRESS)

# Testnet deployment
pnpm deploy:testnet

# Mainnet deployment
pnpm deploy:mainnet
```

**Output:**

- Contract address
- Deployment validation (token check, owner verification)
- Verification command for PolygonScan

---

#### Test Deployment (`deploy-test.ts`)

Deploy with MockERC20 for local testing and integration tests.

**Usage:**

```bash
pnpm deploy:local
```

**Output:**

- MockERC20 token address (1M tokens minted)
- SimpleLockup contract address
- Environment variables for subsequent scripts

---

### Management Scripts

#### Create Lockup (`create-lockup-helper.ts`)

Interactive CLI tool for creating lockups with comprehensive validation.

**Environment Variables:**

- `LOCKUP_ADDRESS` (required) - Deployed SimpleLockup contract address

**Usage:**

```bash
export LOCKUP_ADDRESS=0x...
pnpm create-lockup
```

**Interactive Prompts:**

1. **Beneficiary Address** - Recipient of vested tokens
2. **Total Amount** - Token amount (in whole tokens, e.g., 1000000)
3. **Cliff Duration** - Seconds before vesting starts (e.g., 7776000 = 90 days)
4. **Vesting Duration** - Total vesting period in seconds (e.g., 31536000 = 365 days)
5. **Revocable** - Whether owner can revoke (yes/no)

**Common Duration Conversions:**

- 1 day = 86,400 seconds
- 30 days = 2,592,000 seconds
- 90 days = 7,776,000 seconds
- 1 year = 31,536,000 seconds

**Validation Performed:**

- Checks if lockup already exists (SimpleLockup: one per contract)
- Validates address format
- Verifies deployer token balance
- Validates cliff ≤ vesting duration
- Checks token allowance (auto-approves if needed)

**Example Session:**

```
=== Interactive Lockup Creation ===
Your Address: 0xABC...
Your Token Balance: 5000000.0 tokens

📝 Enter Lockup Parameters:
Beneficiary Address: 0xDEF...
Total Amount (in tokens): 1000000
Cliff Duration (in seconds): 7776000
Total Vesting Duration (in seconds): 31536000
Revocable? (yes/no): yes

📊 Lockup Summary:
Beneficiary: 0xDEF...
Amount: 1000000.0 tokens
Cliff Duration: 90 days
Vesting Duration: 365 days
Revocable: true

Proceed? (yes/no): yes

⚠️  Insufficient allowance. Approving tokens...
✅ Tokens approved
🔨 Creating lockup...
✅ Lockup created successfully!
Gas used: 120543
```

---

#### Release Tokens (`release-helper.ts`)

Interactive tool for beneficiaries to claim vested tokens.

**Environment Variables:**

- `LOCKUP_ADDRESS` (required) - SimpleLockup contract address

**Usage:**

```bash
export LOCKUP_ADDRESS=0x...
pnpm release-helper
```

**Behavior:**

- Automatically uses caller's address as beneficiary
- Shows current vesting status and releasable amount
- Validates cliff period has passed
- Requires confirmation before execution
- Displays updated status after release

**Example Session:**

```
=== Interactive Token Release ===
Your Address: 0xDEF...

📊 Your Lockup Information:
Total Amount: 1000000.0 tokens
Released Amount: 250000.0 tokens
Vested Amount: 500000.0 tokens
Releasable Amount: 250000.0 tokens
Vesting Progress: 50%
Remaining Time: 182.5 days

💰 You can release 250000.0 tokens now!

Estimated Gas: 48523

Proceed with token release? (yes/no): yes

🔓 Releasing tokens...
✅ Tokens released successfully!
Gas used: 47892

📊 Updated Status:
Total Released: 500000.0 tokens
Remaining Locked: 500000.0 tokens
```

---

#### Revoke Lockup (`revoke-helper.ts`)

Interactive tool for owner to revoke lockups and reclaim unvested tokens.

**Environment Variables:**

- `LOCKUP_ADDRESS` (required) - SimpleLockup contract address

**Usage:**

```bash
export LOCKUP_ADDRESS=0x...
pnpm revoke-helper
```

**Security Features:**

- Verifies caller is contract owner
- Automatically gets beneficiary from contract
- Shows revocation impact preview
- Double confirmation required (beneficiary address confirmation + "REVOKE")
- ⚠️ **Cannot be undone**

**Example Session:**

```
=== Interactive Lockup Revocation ===
Your Address: 0xABC... (Owner)
Beneficiary: 0xDEF...

📊 Lockup Information:
Total Amount: 1000000.0 tokens
Released Amount: 250000.0 tokens
Vested Amount: 500000.0 tokens
Unvested Amount: 500000.0 tokens

⚠️  Revocation Impact:
✅ Beneficiary keeps: 500000.0 tokens (vested)
📤 Returns to owner: 500000.0 tokens (unvested)

⚠️  WARNING: This action cannot be undone!

Type the beneficiary address to confirm: 0xDEF...
Type "REVOKE" to proceed: REVOKE

🔨 Revoking lockup...
✅ Lockup revoked successfully!

📊 Revoked Lockup Status:
Revoked: true
Vested at Revoke: 500000.0 tokens
Beneficiary can still claim: 250000.0 tokens
```

**Important Notes:**

- Only works on revocable lockups
- Beneficiary keeps all vested tokens (intended behavior)
- Unvested tokens return to owner
- Beneficiary can still claim vested but unreleased tokens

---

### Query & Analysis Scripts

#### Check Lockup Status (`check-lockup.ts`)

Query comprehensive lockup information.

**Environment Variables:**

- `LOCKUP_ADDRESS` (required) - SimpleLockup contract address

**Usage:**

```bash
export LOCKUP_ADDRESS=0x...
pnpm check-lockup
```

**Output:**

```
=== Lockup Details ===
Total Amount: 1000000.0 tokens
Released Amount: 250000.0 tokens
Vested Amount: 500000.0 tokens
Releasable Amount: 250000.0 tokens

=== Vesting Schedule ===
Start Time: 2024-01-01T00:00:00.000Z
Cliff End: 2024-04-01T00:00:00.000Z
Vesting End: 2025-01-01T00:00:00.000Z

=== Current Status ===
Vesting Progress: 50%
Remaining Time: 182.5 days
Revocable: true
Revoked: false

🔄 Status: Vesting in progress
💰 You can release 250000.0 tokens now!
```

**Use Cases:**

- Check vesting progress
- Verify lockup parameters
- Determine available tokens for release
- Monitor revocation status

---

#### Calculate Vesting Timeline (`calculate-vested.ts`)

Calculate and display vested amounts at different time points.

**Environment Variables:**

- `LOCKUP_ADDRESS` (required) - SimpleLockup contract address

**Usage:**

```bash
export LOCKUP_ADDRESS=0x...
pnpm calculate-vested
```

**Output:**

```
=== Vesting Timeline Calculator ===

📊 Lockup Parameters:
Total Amount: 1000000.0 tokens
Cliff Duration: 90 days
Vesting Duration: 365 days

📅 Vesting Timeline:
Date                Elapsed    Vested %    Vested Amount
-------------------------------------------------------------
2024-01-01         0d         0.0%        0.0
2024-04-01         90d        0.0%        0.0
2024-07-01         182d       50.0%       500000.0
2024-10-01         273d       75.0%       750000.0
2025-01-01         365d       100.0%      1000000.0

📈 Monthly Vesting Breakdown:
Month    Date                Vested %    Vested Amount
-------------------------------------------------------------
M1       2024-02-01         8.2%        82000.0
M2       2024-03-01         16.4%       164000.0
M3       2024-04-01         24.7%       247000.0
...

📍 Current Status:
Vested Amount: 500000.0 tokens
Vesting Progress: 50%
```

**Use Cases:**

- Financial planning and forecasting
- Beneficiary communication
- Milestone tracking
- Release planning

---

#### List Contract Info (`list-lockups.ts`)

Display SimpleLockup contract information and usage instructions.

**Environment Variables:**

- `LOCKUP_ADDRESS` (required) - SimpleLockup contract address

**Usage:**

```bash
export LOCKUP_ADDRESS=0x...
pnpm list-lockups
```

**Output:**

- Token address
- Contract owner
- Beneficiary address
- Note: SimpleLockup has one lockup per contract (single beneficiary)

---

### Debugging Scripts

#### Debug Lockup Creation (`debug-lockup.ts`)

Diagnostic tool for troubleshooting lockup issues.

**Environment Variables:**

- `LOCKUP_ADDRESS` (required) - SimpleLockup contract address

**Usage:**

```bash
export LOCKUP_ADDRESS=0x...
pnpm debug-lockup
```

**Diagnostics Performed:**

- Contract ownership verification
- Token balance checks (deployer and contract)
- Allowance verification
- Existing lockup detection
- Dry run gas estimation
- Error analysis with recommendations

**Example Output:**

```
🔍 Debugging Lockup Creation

=== Contract Information ===
Token Address: 0x98965...
Owner: 0xABC...
Deployer: 0xABC...
Is Owner?: true

=== Token Balances ===
Deployer Token Balance: 5000000.0 tokens
Contract Token Balance: 0.0 tokens

=== Allowance ===
Current Allowance: 0.0 tokens
⚠️  Issue: No allowance granted

=== Existing Lockup Check ===
Total Amount: 0.0
Lockup Exists?: false

=== Dry Run (estimateGas) ===
❌ Error: ERC20InsufficientAllowance

=== Recommendations ===
1. Approve tokens: token.approve(lockupAddress, amount)
2. Then create lockup: lockup.createLockup(...)
```

**Common Issues Detected:**

- Not the contract owner
- Insufficient token allowance
- Insufficient token balance
- Lockup already exists for beneficiary

---

### Testing Scripts

#### Integration Tests (`run-integration-tests.sh`)

Orchestrate Docker-based integration testing with automatic cleanup.

**Usage:**

```bash
pnpm integration-tests
```

**Workflow:**

1. Start Hardhat node in Docker container
2. Wait for node readiness (health checks with retries)
3. Deploy test contracts (MockERC20 + SimpleLockup)
4. Run integration tests locally
5. Cleanup Docker resources
6. Return test exit code (for CI/CD compatibility)

**Output:**

```
🚀 Starting Integration Tests...
📦 Starting hardhat node via docker-compose...
⏳ Waiting for hardhat node to be ready...
  Attempt 1/30...
  Attempt 2/30...
✅ Hardhat node is ready
🔨 Deploying test contracts...
🧪 Running integration tests...
[Test results...]
🧹 Cleaning up...
✅ Integration tests completed successfully!
```

**Requirements:**

- Docker installed and running
- docker-compose available

---

## Environment Variables Reference

### Required for Production

| Variable        | Required For               | Example Value                                                                                                    |
| --------------- | -------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `PRIVATE_KEY`   | All production deployments | `0x1234...abcd`                                                                                                  |
| `TOKEN_ADDRESS` | Network deployment         | `0x98965474EcBeC2F532F1f780ee37b0b05F77Ca55` (mainnet)<br>`0xE4C687167705Abf55d709395f92e254bdF5825a2` (testnet) |

### Optional Configuration

| Variable                | Purpose               | Default                               |
| ----------------------- | --------------------- | ------------------------------------- |
| `POLYGON_RPC_URL`       | Mainnet RPC endpoint  | `https://polygon-rpc.com`             |
| `AMOY_RPC_URL`          | Testnet RPC endpoint  | `https://rpc-amoy.polygon.technology` |
| `ETHERSCAN_API_KEY`     | Contract verification | None                                  |
| `COINMARKETCAP_API_KEY` | Gas price reporting   | None                                  |
| `REPORT_GAS`            | Enable gas reporting  | `false`                               |

### Script-Specific Runtime

| Variable         | Used By              | Purpose                                          |
| ---------------- | -------------------- | ------------------------------------------------ |
| `LOCKUP_ADDRESS` | Most utility scripts | Target deployed SimpleLockup contract (required) |

---

## Common Workflows

### 1. First Time Setup & Deployment

```bash
# 1. Install dependencies
pnpm install

# 2. Configure environment
cp .env.example .env
# Edit .env with your PRIVATE_KEY and TOKEN_ADDRESS

# 3. Test locally
pnpm test
pnpm integration-tests

# 4. Deploy to testnet (.env file is automatically loaded)
pnpm deploy:testnet

# 5. Verify contract
pnpm verify:testnet

# 6. Save LOCKUP_ADDRESS from deployment output for helper scripts
export LOCKUP_ADDRESS=0x...
```

---

### 2. Creating Your First Lockup

```bash
# Set your deployed contract address
export LOCKUP_ADDRESS=0x...

# Use interactive creation tool
pnpm create-lockup

# Verify lockup was created
pnpm check-lockup

# Calculate vesting timeline
pnpm calculate-vested
```

---

### 3. Beneficiary: Releasing Vested Tokens

```bash
# Set contract address
export LOCKUP_ADDRESS=0x...

# Check your lockup status
pnpm check-lockup

# If tokens are available, release them
pnpm release-helper
```

---

### 4. Owner: Revoking a Lockup

```bash
# Set contract address
export LOCKUP_ADDRESS=0x...

# Check current status
pnpm check-lockup

# Revoke lockup (owner only)
pnpm revoke-helper
# Follow prompts and confirm twice

# Verify revocation
pnpm check-lockup
```

---

### 5. Troubleshooting Lockup Creation

```bash
# Set contract address
export LOCKUP_ADDRESS=0x...

# Run diagnostic tool
pnpm debug-lockup

# Follow recommendations:
# - Approve tokens if needed
# - Check owner permissions
# - Check existing lockup status
```

---

## Build & Test Commands

### Development

```bash
pnpm build              # Compile contracts
pnpm clean              # Clean build artifacts
pnpm test               # Run unit tests
pnpm test:coverage      # Generate coverage report
pnpm test:integration   # Run integration tests only
pnpm integration-tests  # Full Docker test suite
```

### Code Quality

```bash
pnpm lint               # Run ESLint
pnpm lint:fix           # Fix linting issues automatically
pnpm format             # Format code with Prettier
```

### Network Operations

```bash
pnpm deploy:mainnet     # Deploy to Polygon mainnet
pnpm deploy:testnet     # Deploy to Amoy testnet
pnpm deploy:local       # Deploy to local Hardhat network
pnpm verify:mainnet     # Verify on PolygonScan mainnet
pnpm verify:testnet     # Verify on PolygonScan testnet
```

## License

MIT

## Support

For issues or questions, please open a GitHub issue.
