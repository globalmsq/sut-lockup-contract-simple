// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title SimpleLockup
 * @notice Minimal token lockup with linear vesting - one lockup per contract
 * @dev Implements linear vesting with cliff period, simplified from TokenLockup
 *
 * Key Design Decisions:
 * - One lockup per contract: Single beneficiary per deployment, simplifies state management
 * - Immutable token: Cannot be changed after deployment for security and predictability
 * - Pull payment pattern: Beneficiaries initiate withdrawals (gas-efficient, secure)
 * - Integer division: Uses standard Solidity division for vesting calculations
 *   * Sub-token precision loss is acceptable for simplicity and gas efficiency
 *   * No cumulative error: Each vesting calculation is independent
 *   * Completion guarantee: All remaining tokens released at vesting end
 *
 * @custom:security-considerations
 * - ERC-777 tokens: Deployer must verify token contract doesn't implement reentrancy hooks
 * - ReentrancyGuard: Applied for defense-in-depth despite Checks-Effects-Interactions pattern
 * - Ownable: Only contract owner can create and revoke lockups
 * - Immutable design: No upgradeability to minimize attack surface
 */
contract SimpleLockup is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct LockupInfo {
        uint256 totalAmount;
        uint256 releasedAmount;
        uint64 startTime;
        uint64 cliffDuration;
        uint64 vestingDuration;
        bool revocable;
        bool revoked;
        uint256 vestedAtRevoke; // Amount vested at revocation time (0 if not revoked)
    }

    IERC20 public immutable token;
    LockupInfo public lockupInfo;
    address public beneficiary;

    // Constants
    uint256 public constant MAX_VESTING_DURATION = 10 * 365 days; // 10 years

    event TokensLocked(
        address indexed beneficiary,
        uint256 amount,
        uint64 startTime,
        uint64 cliffDuration,
        uint64 vestingDuration,
        bool revocable
    );
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event LockupRevoked(address indexed beneficiary, uint256 refundAmount);

    error InvalidAmount();
    error InvalidDuration();
    error InvalidBeneficiary();
    error InvalidTokenAddress();
    error LockupAlreadyExists();
    error NoLockupFound();
    error NoTokensAvailable();
    error NotRevocable();
    error AlreadyRevoked();
    error NotBeneficiary();
    error InsufficientBalance();
    error InsufficientAllowance();
    error InsufficientTokensReceived(uint256 received, uint256 expected);
    error NothingToRevoke();

    /**
     * @notice Constructor
     * @param _token Address of the ERC20 token to be locked
     * @dev Validates that token address contains contract code
     *
     * @custom:security Token Compatibility
     *      This contract is designed for STANDARD ERC-20 tokens only.
     *
     *      INCOMPATIBLE with:
     *      - ERC-777 tokens: reentrancy risk via tokensReceived/tokensToSend hooks
     *      - Deflationary tokens: transfer fees cause balance mismatch (auto-detected and rejected)
     *      - Rebasing tokens: balance changes over time (e.g., stETH, aTokens)
     *
     *      VALIDATION:
     *      The contract validates actual received amount during lockup creation.
     *      Transactions will revert if received amount < expected amount.
     *
     *      Deployer must verify token contract source code before deployment.
     */
    constructor(address _token) Ownable(msg.sender) {
        if (_token == address(0)) revert InvalidTokenAddress();

        // Verify contract code exists at the address
        uint256 size;
        assembly {
            size := extcodesize(_token)
        }
        if (size == 0) revert InvalidTokenAddress();

        // Set token address (deployer must verify ERC20 compatibility)
        token = IERC20(_token);
    }

    /**
     * @notice Create a new lockup for a beneficiary
     * @param _beneficiary Address that will receive the tokens (cannot be zero or this contract)
     * @param amount Total amount of tokens to lock (must be > 0, no maximum enforced)
     * @param cliffDuration Duration of cliff period in seconds (must be < vestingDuration for gradual vesting)
     * @param vestingDuration Total vesting duration in seconds (must be > 0, max = 10 years)
     * @param revocable Whether the lockup can be revoked by owner
     *
     * @dev Validations (optimized for gas efficiency):
     *      1. Lockup uniqueness: Only one lockup per contract instance
     *      2. Amount: > 0 (no maximum, caller must ensure reasonable value)
     *      3. Vesting duration: > 0, <= 10 years (MAX_VESTING_DURATION)
     *      4. Cliff duration: < vesting duration (strictly less to ensure gradual vesting)
     *      5. Beneficiary: non-zero, not this contract
     *      6. Owner balance: >= amount
     *      7. Owner allowance: >= amount
     *      8. Actual received: >= amount (prevents deflationary token issues)
     *
     * @custom:security Protected by nonReentrant modifier for defense-in-depth against
     *      ERC-777 reentrancy attacks via tokensReceived/tokensToSend hooks.
     *      Primary protection comes from Checks-Effects-Interactions pattern.
     *      Additional validation: Checks actual received amount to detect deflationary tokens.
     *
     * @custom:gas-considerations
     *      - First SSTORE to beneficiary: ~20k gas
     *      - First SSTORE to lockupInfo: ~20k gas per field
     *      - Balance/allowance checks: ~2.6k gas each
     *      - SafeTransferFrom: ~50k gas
     *      - Total: ~180-200k gas
     */
    function createLockup(
        address _beneficiary,
        uint256 amount,
        uint64 cliffDuration,
        uint64 vestingDuration,
        bool revocable
    ) external onlyOwner nonReentrant {
        // 1. SLOAD checks (most important check first)
        if (beneficiary != address(0)) revert LockupAlreadyExists();

        // 2. Simple parameter checks
        if (amount == 0) revert InvalidAmount();
        if (vestingDuration == 0) revert InvalidDuration();

        // 3. Comparison operations
        if (cliffDuration >= vestingDuration) revert InvalidDuration();
        if (vestingDuration > MAX_VESTING_DURATION) revert InvalidDuration();

        // 4. Address validations
        if (_beneficiary == address(0)) revert InvalidBeneficiary();
        if (_beneficiary == address(this)) revert InvalidBeneficiary();

        // 5. External calls (most expensive validations)
        uint256 ownerBalance = token.balanceOf(msg.sender);
        uint256 allowance = token.allowance(msg.sender, address(this));

        if (ownerBalance < amount) revert InsufficientBalance();
        if (allowance < amount) revert InsufficientAllowance();

        // Record balance before transfer
        uint256 balanceBefore = token.balanceOf(address(this));

        beneficiary = _beneficiary;
        lockupInfo = LockupInfo({
            totalAmount: amount,
            releasedAmount: 0,
            startTime: uint64(block.timestamp),
            cliffDuration: cliffDuration,
            vestingDuration: vestingDuration,
            revocable: revocable,
            revoked: false,
            vestedAtRevoke: 0
        });

        token.safeTransferFrom(msg.sender, address(this), amount);

        // Validate actual received amount (handles deflationary tokens)
        uint256 balanceAfter = token.balanceOf(address(this));
        uint256 actualReceived = balanceAfter - balanceBefore;

        if (actualReceived < amount) {
            revert InsufficientTokensReceived(actualReceived, amount);
        }

        emit TokensLocked(_beneficiary, amount, uint64(block.timestamp), cliffDuration, vestingDuration, revocable);
    }

    /**
     * @notice Release vested tokens to beneficiary
     * @dev Beneficiaries can claim vested tokens even after revocation.
     *      After full vesting period, all remaining tokens (including rounding dust) are released.
     *      Uses pull payment pattern for gas efficiency.
     * @custom:security Protected by ReentrancyGuard
     */
    function release() external nonReentrant {
        if (msg.sender != beneficiary) revert NotBeneficiary();
        if (lockupInfo.totalAmount == 0) revert NoLockupFound();

        uint256 releasable = _releasableAmount();
        if (releasable == 0) revert NoTokensAvailable();

        lockupInfo.releasedAmount += releasable;
        token.safeTransfer(msg.sender, releasable);

        emit TokensReleased(msg.sender, releasable);
    }

    /**
     * @notice Revoke the lockup and return unvested tokens to owner
     * @dev Freezes vesting at current amount by explicitly storing vestedAtRevoke.
     *      Beneficiary can still claim vested tokens up to the revoked amount.
     *      Original totalAmount and vestingDuration remain unchanged for transparency.
     *
     * @custom:behavior Cliff Period Revocation
     *      - If revoked BEFORE cliff ends:
     *        * Vested amount: 0 tokens
     *        * Beneficiary receives: NOTHING
     *        * Owner receives: 100% of totalAmount
     *        * This is INTENDED - no vesting occurs during cliff
     *
     *      - If revoked AFTER cliff but during vesting:
     *        * Beneficiary keeps all vested tokens (intended, not vulnerability)
     *        * Owner receives unvested tokens
     *        * Beneficiary can still claim vested amount
     *
     * @custom:example Cliff Period Revoke
     *      T=0: Lockup created (1000 tokens, 90-day cliff, 1-year vesting)
     *      T=45 days: Owner calls revoke() (DURING cliff)
     *      Result: Owner receives 1000 tokens, beneficiary receives 0
     *      Status: Correct - cliff period means NO vesting yet
     *
     * @custom:example Post-Cliff Revoke
     *      T=0: Lockup created (1000 tokens, 90-day cliff, 1-year vesting)
     *      T=6 months: 500 tokens vested, owner calls revoke()
     *      Result: Beneficiary keeps 500, owner receives 500
     *      Status: Fair - beneficiary earned those 500 tokens
     *
     * @custom:behavior Beneficiary Rights After Revocation
     *      - Beneficiary KEEPS all tokens vested at the time of revocation
     *      - Revocation stops FUTURE vesting only, does not confiscate vested tokens
     *      - If beneficiary calls release() before owner calls revoke(), this is acceptable
     *      - "Front-running" revoke with release() is NOT an attack - it's fair usage
     *      - Design rationale: Revocation is for stopping future benefits, not punishing past work
     *
     * @custom:security Only revocable lockups can be revoked. Cannot be revoked twice.
     *      Protected by ReentrancyGuard for defense-in-depth.
     */
    function revoke() external onlyOwner nonReentrant {
        if (lockupInfo.totalAmount == 0) revert NoLockupFound();
        if (lockupInfo.revoked) revert AlreadyRevoked();
        if (!lockupInfo.revocable) revert NotRevocable();

        uint256 vested = _vestedAmount();
        // Note: mathematically vested cannot exceed totalAmount due to
        // formula in _vestedAmount(), but keeping check for defense-in-depth
        if (vested > lockupInfo.totalAmount) {
            vested = lockupInfo.totalAmount;
        }
        uint256 refund = lockupInfo.totalAmount - vested;

        // Prevent meaningless revocation when nothing to revoke
        if (refund == 0) revert NothingToRevoke();

        lockupInfo.revoked = true;
        lockupInfo.vestedAtRevoke = vested; // Explicitly store vested amount at revocation

        token.safeTransfer(owner(), refund);

        emit LockupRevoked(beneficiary, refund);
    }

    /**
     * @notice Get the amount of tokens that can be released
     * @return Amount of releasable tokens
     */
    function releasableAmount() external view returns (uint256) {
        return _releasableAmount();
    }

    /**
     * @notice Get the amount of vested tokens
     * @return Amount of vested tokens
     */
    function vestedAmount() external view returns (uint256) {
        return _vestedAmount();
    }

    /**
     * @notice Get vesting progress as percentage
     * @return Vesting progress (0-100)
     * @dev Returns 100 for revoked or fully vested lockups
     *      Returns 0 before cliff period or for non-existent lockups
     */
    function getVestingProgress() external view returns (uint256) {
        // No lockup exists
        if (lockupInfo.totalAmount == 0) {
            return 0;
        }

        // Revoked lockups are considered 100% complete (vesting is frozen/determined)
        if (lockupInfo.revoked) {
            return 100;
        }

        // Before cliff period
        if (block.timestamp < lockupInfo.startTime + lockupInfo.cliffDuration) {
            return 0;
        }

        // After vesting completion
        if (block.timestamp >= lockupInfo.startTime + lockupInfo.vestingDuration) {
            return 100;
        }

        // During vesting period: calculate percentage
        uint256 elapsed = block.timestamp - lockupInfo.startTime;
        return (elapsed * 100) / lockupInfo.vestingDuration;
    }

    /**
     * @notice Get remaining vesting time in seconds
     * @return Remaining time in seconds (0 if completed, revoked, or non-existent)
     */
    function getRemainingVestingTime() external view returns (uint256) {
        // No lockup exists
        if (lockupInfo.totalAmount == 0) {
            return 0;
        }

        // Revoked lockups have no remaining time (vesting is frozen)
        if (lockupInfo.revoked) {
            return 0;
        }

        uint256 endTime = lockupInfo.startTime + lockupInfo.vestingDuration;

        // Vesting already completed
        if (block.timestamp >= endTime) {
            return 0;
        }

        // Return remaining seconds
        return endTime - block.timestamp;
    }

    /**
     * @notice Internal function to calculate releasable amount
     * @dev At the end of vesting period, releases all remaining tokens to eliminate rounding dust
     */
    function _releasableAmount() private view returns (uint256) {
        uint256 vested = _vestedAmount();

        // If fully vested and not revoked, release all remaining tokens (eliminates rounding errors)
        if (!lockupInfo.revoked && block.timestamp >= lockupInfo.startTime + lockupInfo.vestingDuration) {
            return lockupInfo.totalAmount - lockupInfo.releasedAmount;
        }

        return vested - lockupInfo.releasedAmount;
    }

    /**
     * @notice Internal function to calculate vested amount
     * @dev Uses linear vesting formula: (totalAmount × timeFromStart) / vestingDuration
     *      Uses Math.mulDiv to prevent integer overflow for large amounts.
     *      Integer division rounds down. Any rounding dust is released at vesting end.
     *      For revoked lockups, returns the explicitly stored vestedAtRevoke amount.
     *
     * @custom:precision Rounding Behavior and Error Analysis
     *      - Rounding error: < 1 token per calculation (Solidity integer division)
     *      - NO cumulative error: Each calculation is independent, not incremental
     *      - Auto-correction: Errors self-correct in subsequent releases
     *      - Overflow protection: Math.mulDiv prevents overflow for large amounts
     *
     *      Example (50,000,000 tokens vested over 10 years):
     *        Day 1: vested = 13,698 tokens (actual: 13,698.63)
     *               release = 13,698, releasedAmount = 13,698
     *        Day 2: vested = 27,397 tokens (actual: 27,397.26)
     *               release = 27,397 - 13,698 = 13,699 (error corrected!)
     *        ...
     *        Last day: release = totalAmount - releasedAmount (all remaining)
     *
     *      Revocation precision:
     *        - At revoke: vestedAtRevoke stores calculated vested amount
     *        - Maximum loss: < 1 token (e.g., 0.000002% for 50M tokens)
     *        - This is acceptable for gas efficiency vs precision tradeoff
     */
    function _vestedAmount() private view returns (uint256) {
        if (lockupInfo.totalAmount == 0) {
            return 0;
        }

        // If revoked, return the explicitly stored vested amount at revocation time
        if (lockupInfo.revoked) {
            return lockupInfo.vestedAtRevoke;
        }

        if (block.timestamp < lockupInfo.startTime + lockupInfo.cliffDuration) {
            return 0;
        }

        if (block.timestamp >= lockupInfo.startTime + lockupInfo.vestingDuration) {
            return lockupInfo.totalAmount;
        }

        uint256 timeFromStart = block.timestamp - lockupInfo.startTime;

        // Use Math.mulDiv to prevent overflow for large amounts
        uint256 vested = Math.mulDiv(lockupInfo.totalAmount, timeFromStart, lockupInfo.vestingDuration);

        return vested;
    }
}
