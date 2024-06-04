dev:
	forge test -vvvv --match-contract PutETH --fork-url https://eth-mainnet.g.alchemy.com/v2/38A3rlBUZpErpHxQnoZlEhpRHSu4a7VB --fork-block-number 19955703 --match-test test_osqth_operations
devc:
	forge test -vv --match-contract PutETH --fork-url https://eth-mainnet.g.alchemy.com/v2/38A3rlBUZpErpHxQnoZlEhpRHSu4a7VB --fork-block-number 19955703 --match-test test_osqth_operations
deva:
	forge test -vv --match-contract PutETH --fork-url https://eth-mainnet.g.alchemy.com/v2/38A3rlBUZpErpHxQnoZlEhpRHSu4a7VB --fork-block-number 19955703
spell:
	cspell "**/*.{sol,md}"