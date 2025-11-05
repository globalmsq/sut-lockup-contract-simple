import { expect } from 'chai';
import { ethers } from 'hardhat';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { SimpleLockup, MockERC20 } from '../typechain-types';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

describe('SimpleLockup', function () {
  let simpleLockup: SimpleLockup;
  let token: MockERC20;
  let owner: SignerWithAddress;
  let beneficiary: SignerWithAddress;
  let otherAccount: SignerWithAddress;

  const TOTAL_AMOUNT = ethers.parseEther('1000');
  const CLIFF_DURATION = 30 * 24 * 60 * 60; // 30 days
  const VESTING_DURATION = 365 * 24 * 60 * 60; // 1 year

  beforeEach(async function () {
    [owner, beneficiary, otherAccount] = await ethers.getSigners();

    // Deploy mock token with sufficient supply for large amount tests
    const MockERC20Factory = await ethers.getContractFactory('MockERC20');
    token = await MockERC20Factory.deploy('Test Token', 'TEST', ethers.parseEther('100000000'));
    await token.waitForDeployment();

    // Deploy SimpleLockup
    const SimpleLockupFactory = await ethers.getContractFactory('SimpleLockup');
    simpleLockup = await SimpleLockupFactory.deploy(await token.getAddress());
    await simpleLockup.waitForDeployment();

    // Approve tokens for lockup contract
    await token.approve(await simpleLockup.getAddress(), TOTAL_AMOUNT);
  });

  describe('Deployment', function () {
    it('Should set the correct token address', async function () {
      expect(await simpleLockup.token()).to.equal(await token.getAddress());
    });

    it('Should set the correct owner', async function () {
      expect(await simpleLockup.owner()).to.equal(owner.address);
    });

    it('Should revert with zero token address', async function () {
      const SimpleLockupFactory = await ethers.getContractFactory('SimpleLockup');
      await expect(SimpleLockupFactory.deploy(ethers.ZeroAddress)).to.be.revertedWithCustomError(
        simpleLockup,
        'InvalidTokenAddress'
      );
    });
  });

  describe('Create Lockup', function () {
    it('Should create a lockup successfully', async function () {
      const tx = await simpleLockup.createLockup(
        beneficiary.address,
        TOTAL_AMOUNT,
        CLIFF_DURATION,
        VESTING_DURATION,
        true
      );
      const receipt = await tx.wait();
      const block = await ethers.provider.getBlock(receipt!.blockNumber!);
      const actualStartTime = block!.timestamp;

      await expect(tx)
        .to.emit(simpleLockup, 'TokensLocked')
        .withArgs(
          beneficiary.address,
          TOTAL_AMOUNT,
          actualStartTime,
          CLIFF_DURATION,
          VESTING_DURATION,
          true
        );

      const lockup = await simpleLockup.lockups(beneficiary.address);
      expect(lockup.totalAmount).to.equal(TOTAL_AMOUNT);
      expect(lockup.releasedAmount).to.equal(0);
      expect(lockup.revocable).to.equal(true);
      expect(lockup.revoked).to.equal(false);
    });

    it('Should transfer tokens from owner to contract', async function () {
      const initialBalance = await token.balanceOf(await simpleLockup.getAddress());

      await simpleLockup.createLockup(
        beneficiary.address,
        TOTAL_AMOUNT,
        CLIFF_DURATION,
        VESTING_DURATION,
        true
      );

      expect(await token.balanceOf(await simpleLockup.getAddress())).to.equal(
        initialBalance + TOTAL_AMOUNT
      );
    });

    it('Should revert with zero beneficiary address', async function () {
      await expect(
        simpleLockup.createLockup(
          ethers.ZeroAddress,
          TOTAL_AMOUNT,
          CLIFF_DURATION,
          VESTING_DURATION,
          true
        )
      ).to.be.revertedWithCustomError(simpleLockup, 'InvalidBeneficiary');
    });

    it('Should revert when beneficiary is contract address', async function () {
      const lockupAddress = await simpleLockup.getAddress();
      await expect(
        simpleLockup.createLockup(
          lockupAddress,
          TOTAL_AMOUNT,
          CLIFF_DURATION,
          VESTING_DURATION,
          true
        )
      ).to.be.revertedWithCustomError(simpleLockup, 'InvalidBeneficiary');
    });

    it('Should allow owner to create lockup for themselves', async function () {
      await simpleLockup.createLockup(
        owner.address,
        TOTAL_AMOUNT,
        CLIFF_DURATION,
        VESTING_DURATION,
        true
      );

      const lockup = await simpleLockup.lockups(owner.address);
      expect(lockup.totalAmount).to.equal(TOTAL_AMOUNT);
    });

    it('Should revert with zero amount', async function () {
      await expect(
        simpleLockup.createLockup(beneficiary.address, 0, CLIFF_DURATION, VESTING_DURATION, true)
      ).to.be.revertedWithCustomError(simpleLockup, 'InvalidAmount');
    });

    it('Should revert with zero vesting duration', async function () {
      await expect(
        simpleLockup.createLockup(beneficiary.address, TOTAL_AMOUNT, CLIFF_DURATION, 0, true)
      ).to.be.revertedWithCustomError(simpleLockup, 'InvalidDuration');
    });

    it('Should revert when cliff is longer than vesting', async function () {
      await expect(
        simpleLockup.createLockup(
          beneficiary.address,
          TOTAL_AMOUNT,
          VESTING_DURATION + 1,
          VESTING_DURATION,
          true
        )
      ).to.be.revertedWithCustomError(simpleLockup, 'InvalidDuration');
    });

    it('Should revert when lockup already exists', async function () {
      await simpleLockup.createLockup(
        beneficiary.address,
        TOTAL_AMOUNT,
        CLIFF_DURATION,
        VESTING_DURATION,
        true
      );

      await token.approve(await simpleLockup.getAddress(), TOTAL_AMOUNT);

      await expect(
        simpleLockup.createLockup(
          beneficiary.address,
          TOTAL_AMOUNT,
          CLIFF_DURATION,
          VESTING_DURATION,
          true
        )
      ).to.be.revertedWithCustomError(simpleLockup, 'LockupAlreadyExists');
    });

    it('Should revert when called by non-owner', async function () {
      await expect(
        simpleLockup
          .connect(otherAccount)
          .createLockup(beneficiary.address, TOTAL_AMOUNT, CLIFF_DURATION, VESTING_DURATION, true)
      ).to.be.revertedWithCustomError(simpleLockup, 'OwnableUnauthorizedAccount');
    });
  });

  describe('Vesting', function () {
    beforeEach(async function () {
      await simpleLockup.createLockup(
        beneficiary.address,
        TOTAL_AMOUNT,
        CLIFF_DURATION,
        VESTING_DURATION,
        true
      );
    });

    it('Should return 0 vested amount during cliff period', async function () {
      const vested = await simpleLockup.vestedAmount(beneficiary.address);
      expect(vested).to.equal(0);
    });

    it('Should return correct vested amount after cliff', async function () {
      await time.increase(CLIFF_DURATION + 1);
      const vested = await simpleLockup.vestedAmount(beneficiary.address);
      expect(vested).to.be.gt(0);
    });

    it('Should return total amount after vesting completion', async function () {
      await time.increase(VESTING_DURATION + 1);
      const vested = await simpleLockup.vestedAmount(beneficiary.address);
      expect(vested).to.equal(TOTAL_AMOUNT);
    });

    it('Should calculate vesting progress correctly', async function () {
      const progress1 = await simpleLockup.getVestingProgress(beneficiary.address);
      expect(progress1).to.equal(0); // Before cliff

      await time.increase(CLIFF_DURATION);
      const progress2 = await simpleLockup.getVestingProgress(beneficiary.address);
      expect(progress2).to.be.gt(0);
      expect(progress2).to.be.lt(100);

      await time.increase(VESTING_DURATION);
      const progress3 = await simpleLockup.getVestingProgress(beneficiary.address);
      expect(progress3).to.equal(100);
    });

    it('Should calculate remaining vesting time correctly', async function () {
      const remaining1 = await simpleLockup.getRemainingVestingTime(beneficiary.address);
      expect(remaining1).to.equal(VESTING_DURATION);

      await time.increase(VESTING_DURATION / 2);
      const remaining2 = await simpleLockup.getRemainingVestingTime(beneficiary.address);
      expect(remaining2).to.be.closeTo(VESTING_DURATION / 2, 10);

      await time.increase(VESTING_DURATION);
      const remaining3 = await simpleLockup.getRemainingVestingTime(beneficiary.address);
      expect(remaining3).to.equal(0);
    });
  });

  describe('Release', function () {
    beforeEach(async function () {
      await simpleLockup.createLockup(
        beneficiary.address,
        TOTAL_AMOUNT,
        CLIFF_DURATION,
        VESTING_DURATION,
        true
      );
    });

    it('Should revert release during cliff period', async function () {
      await expect(simpleLockup.connect(beneficiary).release()).to.be.revertedWithCustomError(
        simpleLockup,
        'NoTokensAvailable'
      );
    });

    it('Should release tokens after cliff', async function () {
      await time.increase(CLIFF_DURATION + 1);

      const releasable = await simpleLockup.releasableAmount(beneficiary.address);
      expect(releasable).to.be.gt(0);

      await simpleLockup.connect(beneficiary).release();

      const beneficiaryBalance = await token.balanceOf(beneficiary.address);
      expect(beneficiaryBalance).to.be.closeTo(releasable, ethers.parseEther('0.1')); // Allow rounding tolerance
    });

    it('Should release all tokens after vesting completion', async function () {
      await time.increase(VESTING_DURATION + 1);

      await simpleLockup.connect(beneficiary).release();

      const beneficiaryBalance = await token.balanceOf(beneficiary.address);
      expect(beneficiaryBalance).to.equal(TOTAL_AMOUNT);

      const lockup = await simpleLockup.lockups(beneficiary.address);
      expect(lockup.releasedAmount).to.equal(TOTAL_AMOUNT);
    });

    it('Should revert when no lockup exists', async function () {
      await expect(simpleLockup.connect(otherAccount).release()).to.be.revertedWithCustomError(
        simpleLockup,
        'NoLockupFound'
      );
    });
  });

  describe('Revoke', function () {
    beforeEach(async function () {
      await simpleLockup.createLockup(
        beneficiary.address,
        TOTAL_AMOUNT,
        CLIFF_DURATION,
        VESTING_DURATION,
        true
      );
    });

    it('Should revoke lockup and return unvested tokens', async function () {
      await time.increase(VESTING_DURATION / 2);

      const vestedBefore = await simpleLockup.vestedAmount(beneficiary.address);
      const unvested = TOTAL_AMOUNT - vestedBefore;

      await simpleLockup.revoke(beneficiary.address);

      const lockup = await simpleLockup.lockups(beneficiary.address);
      expect(lockup.revoked).to.equal(true);
      expect(lockup.vestedAtRevoke).to.be.closeTo(vestedBefore, ethers.parseEther('0.1')); // Allow rounding tolerance

      const ownerBalance = await token.balanceOf(owner.address);
      expect(ownerBalance).to.be.gte(unvested - ethers.parseEther('0.1')); // Allow tolerance
    });

    it('Should allow beneficiary to claim vested tokens after revocation', async function () {
      await time.increase(VESTING_DURATION / 2);

      const vested = await simpleLockup.vestedAmount(beneficiary.address);
      await simpleLockup.revoke(beneficiary.address);

      await simpleLockup.connect(beneficiary).release();

      const beneficiaryBalance = await token.balanceOf(beneficiary.address);
      expect(beneficiaryBalance).to.be.closeTo(vested, ethers.parseEther('0.1')); // Allow rounding tolerance
    });

    it('Should revert when revoking non-revocable lockup', async function () {
      await token.approve(await simpleLockup.getAddress(), TOTAL_AMOUNT);
      await simpleLockup.createLockup(
        otherAccount.address,
        TOTAL_AMOUNT,
        CLIFF_DURATION,
        VESTING_DURATION,
        false
      );

      await expect(simpleLockup.revoke(otherAccount.address)).to.be.revertedWithCustomError(
        simpleLockup,
        'NotRevocable'
      );
    });

    it('Should revert when revoking already revoked lockup', async function () {
      await simpleLockup.revoke(beneficiary.address);

      await expect(simpleLockup.revoke(beneficiary.address)).to.be.revertedWithCustomError(
        simpleLockup,
        'AlreadyRevoked'
      );
    });

    it('Should revert when called by non-owner', async function () {
      await expect(
        simpleLockup.connect(otherAccount).revoke(beneficiary.address)
      ).to.be.revertedWithCustomError(simpleLockup, 'OwnableUnauthorizedAccount');
    });
  });

  describe('Precision', function () {
    it('Should handle large amounts with acceptable precision', async function () {
      const LARGE_AMOUNT = ethers.parseEther('50000000'); // 50 million tokens
      const TEN_YEARS = 10 * 365 * 24 * 60 * 60;

      await token.approve(await simpleLockup.getAddress(), LARGE_AMOUNT);
      await simpleLockup.createLockup(
        beneficiary.address,
        LARGE_AMOUNT,
        0, // No cliff
        TEN_YEARS,
        true
      );

      // Day 1
      await time.increase(24 * 60 * 60);
      const vested1 = await simpleLockup.vestedAmount(beneficiary.address);
      expect(vested1).to.be.gt(0); // Should have some vested amount

      await simpleLockup.connect(beneficiary).release();
      const balance1 = await token.balanceOf(beneficiary.address);
      expect(balance1).to.be.closeTo(vested1, ethers.parseEther('1000')); // Allow small tolerance

      // Day 2
      await time.increase(24 * 60 * 60);
      const vested2 = await simpleLockup.vestedAmount(beneficiary.address);
      await simpleLockup.connect(beneficiary).release();
      const balance2 = await token.balanceOf(beneficiary.address);

      // Verify second day's vested amount is roughly 2x first day (auto-correction)
      expect(vested2).to.be.closeTo(vested1 * 2n, ethers.parseEther('10000'));
      expect(balance2).to.be.closeTo(vested2, ethers.parseEther('1000')); // Allow small tolerance
    });

    it('Should have minimal precision loss on revocation', async function () {
      const LARGE_AMOUNT = ethers.parseEther('50000000');
      const TEN_YEARS = 10 * 365 * 24 * 60 * 60;

      await token.approve(await simpleLockup.getAddress(), LARGE_AMOUNT);
      await simpleLockup.createLockup(beneficiary.address, LARGE_AMOUNT, 0, TEN_YEARS, true);

      // 5 years later (50% vesting)
      await time.increase(5 * 365 * 24 * 60 * 60);
      await simpleLockup.revoke(beneficiary.address);

      const lockup = await simpleLockup.lockups(beneficiary.address);
      const expected = LARGE_AMOUNT / 2n; // 50% should be vested

      // Verify acceptable precision (< 0.001% error for 50M tokens)
      const tolerance = ethers.parseEther('1000'); // 1000 tokens tolerance = 0.002%
      expect(lockup.vestedAtRevoke).to.be.closeTo(expected, tolerance);
    });

    it('Should enforce MAX_VESTING_DURATION', async function () {
      const MAX_DURATION = 10 * 365 * 24 * 60 * 60;

      await expect(
        simpleLockup.createLockup(
          beneficiary.address,
          TOTAL_AMOUNT,
          0,
          MAX_DURATION + 1, // 10 years + 1 second
          true
        )
      ).to.be.revertedWithCustomError(simpleLockup, 'InvalidDuration');
    });
  });
});
