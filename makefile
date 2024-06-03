dev:
	forge test -vvvv --match-contract PutETH --fork-url https://eth-mainnet.g.alchemy.com/v2/38A3rlBUZpErpHxQnoZlEhpRHSu4a7VB --fork-block-number 19955703 --match-test test_deposit
devc:
	forge test -vv --match-contract PutETH --fork-url https://eth-mainnet.g.alchemy.com/v2/38A3rlBUZpErpHxQnoZlEhpRHSu4a7VB --fork-block-number 19955703 --match-test test_deposit
deva:
	forge test -vv --match-contract PutETH --fork-url https://eth-mainnet.g.alchemy.com/v2/38A3rlBUZpErpHxQnoZlEhpRHSu4a7VB --fork-block-number 19955703
spell:
	cspell "**/*.{sol,md}"