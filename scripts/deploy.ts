import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log('Deploying contracts with account:', deployer.address);
  console.log(
    'Account balance:',
    ethers.formatEther(await ethers.provider.getBalance(deployer.address))
  );

  // Get token address from environment (REQUIRED for production deployment)
  const tokenAddress = process.env.TOKEN_ADDRESS;

  if (!tokenAddress) {
    throw new Error(
      'TOKEN_ADDRESS environment variable is required for production deployment.\n' +
        'For Polygon Mainnet: 0x98965474EcBeC2F532F1f780ee37b0b05F77Ca55\n' +
        'For Amoy Testnet: 0xE4C687167705Abf55d709395f92e254bdF5825a2\n' +
        'For testing with MockERC20, use scripts/deploy-test.ts instead.'
    );
  }

  console.log('\nUsing SUT Token at:', tokenAddress);

  // Deploy SimpleLockup
  console.log('\nDeploying SimpleLockup...');
  const SimpleLockup = await ethers.getContractFactory('SimpleLockup');
  const simpleLockup = await SimpleLockup.deploy(tokenAddress);
  await simpleLockup.waitForDeployment();

  const lockupAddress = await simpleLockup.getAddress();
  console.log('SimpleLockup deployed to:', lockupAddress);

  // Post-deployment validation
  console.log('\n🔍 Validating deployment...');
  const verifiedToken = await simpleLockup.token();
  const verifiedOwner = await simpleLockup.owner();

  console.log('Token Address (from contract):', verifiedToken);
  console.log('Owner:', verifiedOwner);

  // Validation checks
  const checks = {
    tokenAddressMatch: verifiedToken.toLowerCase() === tokenAddress.toLowerCase(),
    ownerIsDeployer: verifiedOwner.toLowerCase() === deployer.address.toLowerCase(),
  };

  console.log('\n✓ Validation Results:');
  console.log('  Token address correct:', checks.tokenAddressMatch ? '✅' : '❌');
  console.log('  Owner set correctly:', checks.ownerIsDeployer ? '✅' : '❌');

  if (!checks.tokenAddressMatch || !checks.ownerIsDeployer) {
    throw new Error('Deployment validation failed!');
  }

  // Network-specific validation
  const network = await ethers.provider.getNetwork();
  const chainId = network.chainId;

  if (chainId === 137n || chainId === 80002n) {
    const expectedTokens: { [key: string]: string } = {
      '137': '0x98965474EcBeC2F532F1f780ee37b0b05F77Ca55', // Polygon Mainnet SUT
      '80002': '0xE4C687167705Abf55d709395f92e254bdF5825a2', // Amoy Testnet SUT
    };

    const expectedToken = expectedTokens[chainId.toString()];
    if (
      expectedToken &&
      tokenAddress.toLowerCase() !== expectedToken.toLowerCase() &&
      process.env.TOKEN_ADDRESS
    ) {
      console.log('\n⚠️  Warning: Token address does not match expected ERC20 token address');
      console.log('  Expected:', expectedToken);
      console.log('  Actual:', tokenAddress);
    }
  }

  // Save deployment info
  const deploymentInfo = {
    network: network.name,
    chainId: chainId.toString(),
    deployer: deployer.address,
    tokenAddress: tokenAddress,
    simpleLockupAddress: lockupAddress,
    owner: verifiedOwner,
    timestamp: new Date().toISOString(),
  };

  console.log('\n=== Deployment Summary ===');
  console.log(JSON.stringify(deploymentInfo, null, 2));
  console.log('\n✅ Deployment completed and validated successfully!');

  // Verification instructions
  if (process.env.ETHERSCAN_API_KEY) {
    console.log('\n=== Verification Command ===');
    console.log(
      `npx hardhat verify --network ${deploymentInfo.network} ${lockupAddress} ${tokenAddress}`
    );
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
