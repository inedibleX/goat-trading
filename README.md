# <h1 align="left">Goat Trading V1</h1>

### [Documentation](https://goattrading.gitbook.io/goat)

This repository contains all smart contracts for Goat Trading. 

- **[contracts/exchange:](https://github.com/inedibleX/goat-trading/tree/main/contracts/exchange)** Core contracts for Goat Trading Dex.

- **[contracts/periphery:](https://github.com/inedibleX/goat-trading/tree/main/contracts/periphery)** Higher Level contracts for Goat Trading Dex.

- **[contracts/tokens:](https://github.com/inedibleX/goat-trading/tree/main/contracts/tokens)** Different types of token implementation. 

- **[contracts/library:](https://github.com/inedibleX/goat-trading/tree/main/contracts/library)** Library functions for Goat Trading Dex	.

### Getting Started

-  **Initial Setup**
	Create `.env` file and fill values using `.env.example`

	```bash
	npm install
	forge install
	forge remappings > remappings.txt # allows resolve libraries installed with forge or npm
	```

- Test
	```bash
	forge test
	```


### Deployment 

- Simulate all contracts deployment to base sepolia
	```bash
	make deploy_sepolia_base_check
	```

- Deploy all contracts to base sepolia
	```bash
	make deploy_sepolia_base
	```

- Simulate all contracts deployment to base mainnet
	```bash
	make deploy_mainnet_base_check
	```

- Deploy all contracts to base mainnet
	```bash
	make deploy_mainnet_base
	```
