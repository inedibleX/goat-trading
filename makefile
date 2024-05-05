include .env
export $(shell sed 's/=.*//' .env)


deploy_sepolia_base: 
	@echo "Deploying contracts to base sepolia"
	@forge script scripts/Deployer.s.sol:DeployAll --rpc-url $(RPC_BASE_SEPOLIA) --private-key $(PRIVATE_KEY) --broadcast --verify
	@echo "Deployment completed!"
deploy_sepolia_base_check: 
	@echo "Testing contract deployment"
	@forge script scripts/Deployer.s.sol:DeployAll --rpc-url $(RPC_BASE_SEPOLIA) --private-key $(PRIVATE_KEY) 
	@echo "Deployment completed!"
deploy_mainnet_base: 
	@echo "Deploying contracts to base Mainnet"
	@forge script scripts/Deployer.s.sol:DeployAll --rpc-url $(RPC_BASE_MAINNET) --private-key $(PRIVATE_KEY) --broadcast --verify
	@echo "Deployment completed!"
deploy_mainnet_base_check: 
	@echo "Deploying contracts to base Mainnet"
	@forge script scripts/Deployer.s.sol:DeployAll --rpc-url $(RPC_BASE_MAINNET) --private-key $(PRIVATE_KEY) 
	@echo "Deployment completed!"
