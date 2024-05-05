# <h1 align="center">Goat Trading Dex Contracts</h1>

### Getting Started

- Initial Setup
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

- Check all contracts deployment to sepolia-base using makefile
```bash
	make deploy_sepolia_base_check
```

- Deploy all contracts to sepolia-base using makefile
```bash
	make deploy_sepolia_base
```

- Check all contracts deployment to mainnet-base using makefile
```bash
	make deploy_mainnet_base_check
```

- Deploy all contracts to mainnet-base using makefile
```bash
	make deploy_mainnet_base
```