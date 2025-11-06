#!/bin/sh
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "${GREEN}========================================${NC}"
echo "${GREEN}  Production Deployment Script${NC}"
echo "${GREEN}========================================${NC}"

# Set default network if not specified
DEPLOY_NETWORK=${DEPLOY_NETWORK:-localhost}

# Check if TOKEN_ADDRESS is set (only required for production networks)
if [ "$DEPLOY_NETWORK" != "localhost" ] && [ -z "$TOKEN_ADDRESS" ]; then
    echo "${RED}❌ ERROR: TOKEN_ADDRESS environment variable is required for production deployment${NC}"
    echo "${YELLOW}Set TOKEN_ADDRESS to the ERC20 token address for your network:${NC}"
    echo "  Polygon Mainnet: 0x98965474EcBeC2F532F1f780ee37b0b05F77Ca55"
    echo "  Amoy Testnet: 0xE4C687167705Abf55d709395f92e254bdF5825a2"
    exit 1
fi

echo "${GREEN}📋 Configuration:${NC}"
echo "  Network: ${DEPLOY_NETWORK}"
if [ "$DEPLOY_NETWORK" = "localhost" ]; then
    echo "  Mode: Test deployment (MockERC20 + SimpleLockup)"
else
    echo "  Token Address: ${TOKEN_ADDRESS}"
fi
echo ""

# Wait for hardhat-node to be ready (if deploying to localhost)
if [ "$DEPLOY_NETWORK" = "localhost" ]; then
    echo "${YELLOW}⏳ Waiting for hardhat-node to be ready...${NC}"
    MAX_RETRIES=30
    RETRY_COUNT=0

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if wget -q --spider http://hardhat-node:8545 2>/dev/null; then
            echo "${GREEN}✅ Hardhat node is ready!${NC}"
            break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "  Attempt $RETRY_COUNT/$MAX_RETRIES..."
        sleep 2
    done

    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        echo "${RED}❌ ERROR: Hardhat node failed to start${NC}"
        exit 1
    fi
fi

# Run deployment (use deploy-test.ts for localhost, deploy.ts for production)
if [ "$DEPLOY_NETWORK" = "localhost" ]; then
    echo "${GREEN}🚀 Running test deployment (MockERC20 + SimpleLockup)...${NC}"
    npx hardhat run scripts/deploy-test.ts --network ${DEPLOY_NETWORK}
else
    echo "${GREEN}🚀 Running production deployment...${NC}"
    npx hardhat run scripts/deploy.ts --network ${DEPLOY_NETWORK}
fi

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo "${GREEN}========================================${NC}"
    echo "${GREEN}✅ Deployment completed successfully!${NC}"
    echo "${GREEN}========================================${NC}"
else
    echo "${RED}========================================${NC}"
    echo "${RED}❌ Deployment failed with exit code ${EXIT_CODE}${NC}"
    echo "${RED}========================================${NC}"
    exit $EXIT_CODE
fi
