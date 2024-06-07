dev:
	forge test -vvvv --match-contract PutETHTest --fork-url https://eth-mainnet.g.alchemy.com/v2/38A3rlBUZpErpHxQnoZlEhpRHSu4a7VB --fork-block-number 19955703 --match-test test_deposit_withdraw
devc:
	forge test -vv --match-contract PutETHTest --fork-url https://eth-mainnet.g.alchemy.com/v2/38A3rlBUZpErpHxQnoZlEhpRHSu4a7VB --fork-block-number 19955703 --match-test test_deposit_withdraw
deva:
	forge test -vv --match-contract ETHTest --fork-url https://eth-mainnet.g.alchemy.com/v2/38A3rlBUZpErpHxQnoZlEhpRHSu4a7VB --fork-block-number 19955703
t:
	forge test -vvvv --match-contract OptionBaseLibTest
spell:
	cspell "**/*.{sol,md}"