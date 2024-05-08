include .env
export $(shell sed 's/=.*//' .env)


deploy_all_sepolia_base: 
	@echo "Deploying contracts to base sepolia"
	@forge script scripts/Deployer.s.sol:DeployAll --rpc-url $(RPC_BASE_SEPOLIA) --private-key $(PRIVATE_KEY) --broadcast --verify -vvvvv
	@echo "Deployment completed!"
deploy_all_sepolia_base_check: 
	@echo "Testing contract deployment"
	@forge script scripts/Deployer.s.sol:DeployAll --rpc-url $(RPC_BASE_SEPOLIA) --private-key $(PRIVATE_KEY) 
	@echo "Deployment completed!"
deploy_all_mainnet_base: 
	@echo "Deploying contracts to base Mainnet"
	@forge script scripts/Deployer.s.sol:DeployAll --rpc-url $(RPC_BASE_MAINNET) --private-key $(PRIVATE_KEY) --broadcast --verify -vvvvv
	@echo "Deployment completed!"
deploy_all_mainnet_base_check: 
	@echo "Deploying contracts to base Mainnet"
	@forge script scripts/Deployer.s.sol:DeployAll --rpc-url $(RPC_BASE_MAINNET) --private-key $(PRIVATE_KEY) 
	@echo "Deployment completed!"

deploy_factories_base_mainnet: 
	@echo "Deploying contracts to base Mainnet"
	@forge script scripts/Deployer.s.sol:DeployTokenFactories --rpc-url $(RPC_BASE_MAINNET) --private-key $(PRIVATE_KEY) --broadcast --verify -vvvvv
	@echo "Deployment completed!"
deploy_factories_base_mainnet_check: 
	@echo "Deploying contracts to base Mainnet"
	@forge script scripts/Deployer.s.sol:DeployTokenFactories --rpc-url $(RPC_BASE_MAINNET) --private-key $(PRIVATE_KEY) 
	@echo "Deployment completed!"
