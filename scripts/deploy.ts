import { ethers } from 'hardhat';

/**
 * Validate that the provided address is a valid ERC20 token
 * @param tokenAddress Address to validate
 * @throws Error if validation fails
 */
async function validateTokenAddress(tokenAddress: string): Promise<void> {
  console.log('\n🔍 Validating Token Address...');
  console.log('Token Address:', tokenAddress);

  // 1. Basic address validation
  if (!ethers.isAddress(tokenAddress)) {
    throw new Error(
      `❌ Invalid address format: ${tokenAddress}\n` + 'Please provide a valid Ethereum address.'
    );
  }

  if (tokenAddress === ethers.ZeroAddress) {
    throw new Error('❌ Zero address is not allowed for token.');
  }

  // 2. Check if address contains contract code
  const code = await ethers.provider.getCode(tokenAddress);
  if (code === '0x') {
    throw new Error(
      `❌ No contract code found at address: ${tokenAddress}\n` +
        'This appears to be an EOA (externally owned account), not a contract.\n' +
        'Please verify the token contract address.'
    );
  }
  console.log('✅ Contract code exists');

  // 3. Validate ERC20 interface
  console.log('\n📋 Validating ERC20 Interface...');

  const tokenContract = await ethers.getContractAt(
    '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol:IERC20Metadata',
    tokenAddress
  );

  try {
    // Try to call ERC20 standard functions
    const [name, symbol, decimals, totalSupply] = await Promise.all([
      tokenContract.name().catch(() => 'N/A'),
      tokenContract.symbol().catch(() => 'N/A'),
      tokenContract.decimals().catch(() => null),
      tokenContract.totalSupply(),
    ]);

    console.log('✅ ERC20 Interface validated');
    console.log('  - Name:', name);
    console.log('  - Symbol:', symbol);
    console.log('  - Decimals:', decimals !== null ? decimals : 'N/A');
    console.log('  - Total Supply:', totalSupply.toString());

    if (decimals === null) {
      console.log('\n⚠️  Warning: decimals() function not available (some old ERC20 tokens)');
    }
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    throw new Error(
      `❌ ERC20 interface validation failed\n` +
        `The contract at ${tokenAddress} does not implement required ERC20 functions.\n\n` +
        `Error: ${errorMessage}\n\n` +
        'Please verify this is a valid ERC20 token contract.'
    );
  }

  // 4. Check for ERC-777 (incompatible)
  console.log('\n🔍 Checking for ERC-777 compatibility...');

  // 4.1 Check ERC-1820 Registry
  const ERC1820_REGISTRY_ADDRESS = '0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24';
  const registryCode = await ethers.provider.getCode(ERC1820_REGISTRY_ADDRESS);

  if (registryCode !== '0x') {
    try {
      const registry = await ethers.getContractAt(
        [
          'function getInterfaceImplementer(address account, bytes32 interfaceHash) external view returns (address)',
        ],
        ERC1820_REGISTRY_ADDRESS
      );

      const ERC777_INTERFACE_HASH = ethers.keccak256(ethers.toUtf8Bytes('ERC777Token'));
      const implementer = await registry.getInterfaceImplementer(
        tokenAddress,
        ERC777_INTERFACE_HASH
      );

      if (implementer !== ethers.ZeroAddress) {
        throw new Error(
          `❌ ERC-777 token detected!\n\n` +
            'This contract is registered as ERC777Token in the ERC-1820 registry.\n' +
            'ERC-777 tokens are INCOMPATIBLE with SimpleLockup due to reentrancy risks.\n\n' +
            'ERC-777 hooks (tokensReceived/tokensToSend) can cause reentrancy attacks.\n' +
            'Please use a standard ERC-20 token instead.'
        );
      }
      console.log('✅ No ERC-777 registration found in ERC-1820 registry');
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      if (errorMessage.includes('ERC-777')) {
        throw error;
      }
      console.log('⚠️  Could not check ERC-1820 registry:', errorMessage);
    }
  } else {
    console.log('ℹ️  ERC-1820 registry not deployed on this network');
  }

  // 4.2 Check for ERC-777 specific functions
  try {
    const erc777Contract = new ethers.Contract(
      tokenAddress,
      ['function granularity() external view returns (uint256)'],
      ethers.provider
    );

    const granularity = await erc777Contract.granularity();

    // If we got here, the function exists
    throw new Error(
      `❌ ERC-777 token detected!\n\n` +
        `The contract implements granularity() function (returned: ${granularity}).\n` +
        'This is an ERC-777 specific function.\n\n' +
        'ERC-777 tokens are INCOMPATIBLE with SimpleLockup due to reentrancy risks.\n' +
        'Please use a standard ERC-20 token instead.'
    );
  } catch (error: unknown) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    if (errorMessage.includes('ERC-777')) {
      throw error;
    }
    // Function doesn't exist or reverted - this is good (not ERC-777)
    console.log('✅ No ERC-777 specific functions detected');
  }

  console.log('\n✅ Token validation passed\n');
}

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

  console.log('\nUsing Token at:', tokenAddress);

  // Validate token address before deployment
  await validateTokenAddress(tokenAddress);

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
