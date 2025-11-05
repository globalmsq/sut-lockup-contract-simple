// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SimpleLockup
 * @notice Minimal token lockup with linear vesting - one lockup per address
 * @dev Implements linear vesting with cliff period, simplified from TokenLockup
 *
 * Key Design Decisions:
 * - One lockup per address: Simplifies state management, reduces gas costs, clear ownership
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
        uint256 startTime;
        uint256 cliffDuration;
        uint256 vestingDuration;
        bool revocable;
        bool revoked;
        uint256 vestedAtRevoke; // Amount vested at revocation time (0 if not revoked)
    }

    IERC20 public immutable token;
    mapping(address => LockupInfo) public lockups;

    // Constants
    uint256 public constant MAX_VESTING_DURATION = 10 * 365 days; // 10 years

    event TokensLocked(
        address indexed beneficiary,
        uint256 amount,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 vestingDuration,
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

    /**
     * @notice Constructor
     * @param _token Address of the ERC20 token to be locked
     * @dev Validates that token address contains contract code
     * @custom:security Deployer must verify ERC20 compatibility before deployment.
     *      Always verify token contract source code to ensure it doesn't implement
     *      ERC-777 hooks (tokensReceived, tokensToSend) which could enable reentrancy.
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
     * @param beneficiary Address that will receive the tokens
     * @param amount Total amount of tokens to lock
     * @param cliffDuration Duration of cliff period in seconds
     * @param vestingDuration Total vesting duration in seconds (including cliff)
     * @param revocable Whether the lockup can be revoked by owner
     * @custom:security Protected by nonReentrant modifier for defense-in-depth against
     *      ERC-777 reentrancy attacks via tokensReceived/tokensToSend hooks.
     *      Primary protection comes from Checks-Effects-Interactions pattern.
     *      Additional protection: nonReentrant adds ~2.4K gas but prevents theoretical attacks.
     */
    function createLockup(
        address beneficiary,
        uint256 amount,
        uint256 cliffDuration,
        uint256 vestingDuration,
        bool revocable
    ) external onlyOwner nonReentrant {
        if (beneficiary == address(0)) revert InvalidBeneficiary();
        if (beneficiary == address(this)) revert InvalidBeneficiary();
        if (amount == 0) revert InvalidAmount();
        if (vestingDuration == 0) revert InvalidDuration();
        if (vestingDuration > MAX_VESTING_DURATION) revert InvalidDuration();
        if (cliffDuration > vestingDuration) revert InvalidDuration();
        if (lockups[beneficiary].totalAmount != 0) revert LockupAlreadyExists();

        lockups[beneficiary] = LockupInfo({
            totalAmount: amount,
            releasedAmount: 0,
            startTime: block.timestamp,
            cliffDuration: cliffDuration,
            vestingDuration: vestingDuration,
            revocable: revocable,
            revoked: false,
            vestedAtRevoke: 0
        });

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit TokensLocked(beneficiary, amount, block.timestamp, cliffDuration, vestingDuration, revocable);
    }

    /**
     * @notice Release vested tokens to beneficiary
     * @dev Beneficiaries can claim vested tokens even after revocation.
     *      After full vesting period, all remaining tokens (including rounding dust) are released.
     *      Uses pull payment pattern for gas efficiency.
     * @custom:security Protected by ReentrancyGuard
     */
    function release() external nonReentrant {
        LockupInfo storage lockup = lockups[msg.sender];
        if (lockup.totalAmount == 0) revert NoLockupFound();

        uint256 releasable = _releasableAmount(msg.sender);
        if (releasable == 0) revert NoTokensAvailable();

        lockup.releasedAmount += releasable;
        token.safeTransfer(msg.sender, releasable);

        emit TokensReleased(msg.sender, releasable);
    }

    /**
     * @notice Revoke a lockup and return unvested tokens to owner
     * @param beneficiary Address of the beneficiary whose lockup to revoke
     * @dev Freezes vesting at current amount by explicitly storing vestedAtRevoke.
     *      Beneficiary can still claim vested tokens up to the revoked amount.
     *      Original totalAmount and vestingDuration remain unchanged for transparency.
     *
     * @custom:behavior Beneficiary Rights After Revocation
     *      - Beneficiary KEEPS all tokens vested at the time of revocation
     *      - This is INTENDED behavior, not a security vulnerability
     *      - Revocation stops FUTURE vesting only, does not confiscate vested tokens
     *      - If beneficiary calls release() before owner calls revoke(), this is acceptable
     *      - "Front-running" revoke with release() is NOT an attack - it's fair usage
     *      - Design rationale: Revocation is for stopping future benefits, not punishing past work
     *
     *      Example timeline:
     *        T=0: Lockup created for 1000 tokens, 1 year vesting
     *        T=6 months: 500 tokens vested, beneficiary has not claimed yet
     *        T=6 months + 1 second: Owner submits revoke() transaction
     *        T=6 months + 1 second: Beneficiary sees pending revoke, calls release()
     *        Result: Beneficiary receives 500 tokens, owner receives 500 tokens back
     *        This is fair and intended - beneficiary earned those 500 tokens over 6 months
     *
     * @custom:security Only revocable lockups can be revoked. Cannot be revoked twice.
     *      Protected by ReentrancyGuard for defense-in-depth.
     */
    function revoke(address beneficiary) external onlyOwner nonReentrant {
        LockupInfo storage lockup = lockups[beneficiary];
        if (lockup.totalAmount == 0) revert NoLockupFound();
        if (lockup.revoked) revert AlreadyRevoked();
        if (!lockup.revocable) revert NotRevocable();

        uint256 vested = _vestedAmount(beneficiary);
        // Ensure vested doesn't exceed totalAmount (defensive check)
        if (vested > lockup.totalAmount) {
            vested = lockup.totalAmount;
        }
        uint256 refund = lockup.totalAmount - vested;

        lockup.revoked = true;
        lockup.vestedAtRevoke = vested; // Explicitly store vested amount at revocation

        if (refund > 0) {
            token.safeTransfer(owner(), refund);
        }

        emit LockupRevoked(beneficiary, refund);
    }

    /**
     * @notice Get the amount of tokens that can be released
     * @param beneficiary Address to check
     * @return Amount of releasable tokens
     */
    function releasableAmount(address beneficiary) external view returns (uint256) {
        return _releasableAmount(beneficiary);
    }

    /**
     * @notice Get the amount of vested tokens
     * @param beneficiary Address to check
     * @return Amount of vested tokens
     */
    function vestedAmount(address beneficiary) external view returns (uint256) {
        return _vestedAmount(beneficiary);
    }

    /**
     * @notice Get vesting progress as percentage
     * @param beneficiary Address to check
     * @return Vesting progress (0-100)
     * @dev Returns 100 for revoked or fully vested lockups
     *      Returns 0 before cliff period or for non-existent lockups
     */
    function getVestingProgress(address beneficiary) external view returns (uint256) {
        LockupInfo memory lockup = lockups[beneficiary];

        // No lockup exists
        if (lockup.totalAmount == 0) {
            return 0;
        }

        // Revoked lockups are considered 100% complete (vesting is frozen/determined)
        if (lockup.revoked) {
            return 100;
        }

        // Before cliff period
        if (block.timestamp < lockup.startTime + lockup.cliffDuration) {
            return 0;
        }

        // After vesting completion
        if (block.timestamp >= lockup.startTime + lockup.vestingDuration) {
            return 100;
        }

        // During vesting period: calculate percentage
        uint256 elapsed = block.timestamp - lockup.startTime;
        return (elapsed * 100) / lockup.vestingDuration;
    }

    /**
     * @notice Get remaining vesting time in seconds
     * @param beneficiary Address to check
     * @return Remaining time in seconds (0 if completed, revoked, or non-existent)
     */
    function getRemainingVestingTime(address beneficiary) external view returns (uint256) {
        LockupInfo memory lockup = lockups[beneficiary];

        // No lockup exists
        if (lockup.totalAmount == 0) {
            return 0;
        }

        // Revoked lockups have no remaining time (vesting is frozen)
        if (lockup.revoked) {
            return 0;
        }

        uint256 endTime = lockup.startTime + lockup.vestingDuration;

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
    function _releasableAmount(address beneficiary) private view returns (uint256) {
        LockupInfo storage lockup = lockups[beneficiary];
        uint256 vested = _vestedAmount(beneficiary);

        // If fully vested and not revoked, release all remaining tokens (eliminates rounding errors)
        if (!lockup.revoked && block.timestamp >= lockup.startTime + lockup.vestingDuration) {
            return lockup.totalAmount - lockup.releasedAmount;
        }

        return vested - lockup.releasedAmount;
    }

    /**
     * @notice Internal function to calculate vested amount
     * @dev Uses linear vesting formula: (totalAmount × timeFromStart) / vestingDuration
     *      Integer division rounds down. Any rounding dust is released at vesting end.
     *      For revoked lockups, returns the explicitly stored vestedAtRevoke amount.
     *
     * @custom:precision Rounding Behavior and Error Analysis
     *      - Rounding error: < 1 token per calculation (Solidity integer division)
     *      - NO cumulative error: Each calculation is independent, not incremental
     *      - Auto-correction: Errors self-correct in subsequent releases
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
    function _vestedAmount(address beneficiary) private view returns (uint256) {
        LockupInfo memory lockup = lockups[beneficiary];

        if (lockup.totalAmount == 0) {
            return 0;
        }

        // If revoked, return the explicitly stored vested amount at revocation time
        if (lockup.revoked) {
            return lockup.vestedAtRevoke;
        }

        if (block.timestamp < lockup.startTime + lockup.cliffDuration) {
            return 0;
        }

        if (block.timestamp >= lockup.startTime + lockup.vestingDuration) {
            return lockup.totalAmount;
        }

        uint256 timeFromStart = block.timestamp - lockup.startTime;

        // Calculate vested amount using simple division (any rounding dust is released at vesting end)
        uint256 vested = (lockup.totalAmount * timeFromStart) / lockup.vestingDuration;

        return vested;
    }
}
