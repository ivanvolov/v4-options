test:
	cd contracts && npx hardhat test

deploy_sepolia:
	cd contracts && npx hardhat deploy --network sepolia

compile:
	cd cmd && go run main.go -mode compile

set_vk_hash:
	cd contracts && npx hardhat run scripts/SetVkHash.ts --network sepolia

prove:
	cd cmd && go run main.go -mode prove -tx 0x337f815bdd288b3ab2a5e83be8e81d5c7c396ce8890e3738a2a2cb006db5812c

send_request:
	cd contracts && npx hardhat run scripts/SendBrevisRequest.ts --network sepolia

check_loyalty:
	cd contracts && npx hardhat run scripts/CheckLoyalty.ts --network sepolia