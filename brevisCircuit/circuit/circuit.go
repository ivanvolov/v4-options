package age

import (
	"github.com/brevis-network/brevis-sdk/sdk"
	"github.com/ethereum/go-ethereum/common"
)

type AppCircuit struct{}

func (c *AppCircuit) Allocate() (maxReceipts, maxStorage, maxTransactions int) {
	// Our app is only ever going to use one storage data at a time so
	// we can simply limit the max number of data for storage to 1 and
	// 0 for all others
	return 0, 0, 1
}

// Quick Deposit periphery contract
var HeadgehogAddress = sdk.ConstUint248(
	common.HexToAddress("0x468363E262999046BAFC5EA954768920ee349358"))

func (c *AppCircuit) Define(api *sdk.CircuitAPI, in sdk.DataInput) error {
	txs := sdk.NewDataStream(api, in.Transactions)

	tx := sdk.GetUnderlying(txs, 0)
	// This is our main check logic
	api.Uint248.AssertIsEqual(tx.To, HeadgehogAddress)
	api.Uint248.AssertIsLessOrEqual(tx.BlockNum, sdk.ConstUint248(17021883))

	// Output variables can be later accessed in our app contract
	api.OutputAddress(tx.From)
	api.OutputUint(64, tx.BlockNum)

	return nil
}
