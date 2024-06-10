package main

import (
	"context"
	"flag"
	"fmt"
	"math/big"
	"path/filepath"

	age "github.com/brevis-network/brevis-quickstart/circuit"
	"github.com/brevis-network/brevis-sdk/sdk"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
)

var mode = flag.String("mode", "", "compile or prove")
var outDir = flag.String("out", "pwd/circuitOut/myBrevisApp", "compilation output dir")
var srsDir = flag.String("srs", "pwd/kzgsrs", "where to cache kzg srs")
var txHash = flag.String("tx", "", "tx hash to prove")
var rpc = flag.String("rpc", "https://gateway.tenderly.co/public/mainnet", "eth json rpc url")

func main() {
	flag.Parse()
	switch *mode {
	case "compile":
		compile()
	case "prove":
		prove()
	default:
		panic(fmt.Errorf("unsupported mode %s", *mode))
	}
}

func compile() {
	appCircuit := &age.AppCircuit{}
	// The compiled circuit, proving key, and verifying key are saved to outDir, and
	// the downloaded SRS in the process is saved to srsDir
	_, _, _, err := sdk.Compile(appCircuit, *outDir, *srsDir)
	check(err)
}

func prove() {
	if len(*txHash) == 0 {
		panic("-tx is required")
	}

	// Loading the previous compile result into memory
	compiledCircuit, pk, vk, err := sdk.ReadSetupFrom(*outDir)

	app, err := sdk.NewBrevisApp()
	check(err)

	// Query the user specified tx
	tx := queryTransaction(common.HexToHash(*txHash))

	// Adding the queried tx
	app.AddTransaction(tx)

	appCircuitAssignment := &age.AppCircuit{}

	// Prove
	fmt.Println(">> Proving the transaction using my circuit")
	circuitInput, err := app.BuildCircuitInput(appCircuitAssignment)
	check(err)
	witness, publicWitness, err := sdk.NewFullWitness(appCircuitAssignment, circuitInput)
	check(err)
	proof, err := sdk.Prove(compiledCircuit, pk, witness)
	check(err)
	err = sdk.WriteTo(proof, filepath.Join(*outDir, "proof-"+*txHash))
	check(err)

	// Test verifying the proof we just generated
	err = sdk.Verify(vk, publicWitness, proof)
	check(err)

	fmt.Println(">> Initiating Brevis request")
	appContract := common.HexToAddress("0xef1B4B164Fd3b7933bfaDb042373560e715Ec5D6")
	refundee := common.HexToAddress("0x164Ef8f77e1C88Fb2C724D3755488bE4a3ba4342")

	calldata, requestId, feeValue, err := app.PrepareRequest(vk, 1, 11155111, refundee, appContract)
	check(err)
	fmt.Printf("calldata %x\n", calldata)
	fmt.Printf("feeValue %d\n", feeValue)
	fmt.Printf("requestId %s\n", requestId)

	// Submit proof to Brevis
	fmt.Println(">> Submitting my proof to Brevis")
	err = app.SubmitProof(proof)
	check(err)

	// Poll Brevis gateway for query status till the final proof is submitted
	// on-chain by Brevis and your contract is called
	fmt.Println(">> Waiting for final proof generation and submission")
	submitTx, err := app.WaitFinalProofSubmitted(context.Background())
	check(err)
	fmt.Printf(">> Final proof submitted: tx hash %s\n", submitTx)

	// [Don't forget to make the transaction that pays the fee by calling Brevis.sendRequest]
}

func queryTransaction(txhash common.Hash) sdk.TransactionData {
	ec, err := ethclient.Dial(*rpc)
	check(err)
	tx, _, err := ec.TransactionByHash(context.Background(), txhash)
	check(err)
	receipt, err := ec.TransactionReceipt(context.Background(), txhash)
	check(err)
	from, err := types.Sender(types.NewLondonSigner(tx.ChainId()), tx)
	check(err)

	gtc := big.NewInt(0)
	gasFeeCap := big.NewInt(0)
	if tx.Type() == types.LegacyTxType {
		gtc = tx.GasPrice()
	} else {
		gtc = tx.GasTipCap()
		gasFeeCap = tx.GasFeeCap()
	}

	return sdk.TransactionData{
		Hash:                common.HexToHash(*txHash),
		ChainId:             tx.ChainId(),
		BlockNum:            receipt.BlockNumber,
		Nonce:               tx.Nonce(),
		GasTipCapOrGasPrice: gtc,
		GasFeeCap:           gasFeeCap,
		GasLimit:            tx.Gas(),
		From:                from,
		To:                  *tx.To(),
		Value:               tx.Value(),
	}
}

func check(err error) {
	if err != nil {
		panic(err)
	}
}
