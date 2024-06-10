# Deploying and using the circuit contract quick guide 
We are using makefile to run commands

### 1. Test the HedgehogLoyalty contract before deployment
```
make test
```

### 2. Deploy the HedgehogLoyalty contract to the sepolia network
```
make deploy_sepolia
```

### 3. Compile the circuit
```
make compile
```

### 4. Send the vkHash from the previous step to the HedgehogLoyalty contract
- change the `const deployContractAddress` in the `scripts/SetVkHash.ts` file to the address of the deployed HedgehogLoyalty contract obtain from the step 2.
- Then change the `const vkHash` in the `scripts/SetVkHash.ts` file to the vkHash obtained from the step 3.
```
make set_vk_hash
```

### 5. Now you could prove the circuit using the tx witch was the part of the Hedgehog strategy and meet the requirements
```
make prove
```

### 6. Now you could pay the fee on Brevis
- First change the `const requestId` in the `scripts/SendBrevisRequest.ts` file to the requestId obtained from the step 5.
- Then change the `const _callback` in the `scripts/SendBrevisRequest.ts` file to the address of the deployed HedgehogLoyalty contract obtain from the step 2.
```
make send_request`
```

### 7. Now you could check the if the data was submitted correctly to the HedgehogLoyalty contract
```
make check_loyalty
```

#### Here is the example of the transaction used during testing.
```
final proof for query 2d057d9ed09b8ab05a6c29bb29b7d0bc64e743956da5d5bdc87acb727e871aa1 
submitted: tx 0x385e94ddfedd2dc3fa30e2a80eada4b69713ad685659e640518acae78180c106
```