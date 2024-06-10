##  Call like wstETH option using V4 + oSQTH + Morpho hooks

### Hook Flow

weight = 50%

**deposit wstETH**

1. provide 50% of wstETH into liquidity range [current_price, current_price*priceScalingFactor]
2. collateral 50% of wstETH on Morpho pool

**withdraw wstETH**

1. close uniswap position into wstETH and USDC 
2. swap all oSQTH into wstETH
2. repay borrow on Morpho using USDC (extra usdc could be bought with wstETH)
3. withdraw wstETH from Morpho
4. swap USDC (if remained) into wstETH and transfer all wstETH to user

**swap: price go up**

1. borrow USDC = delta_amount1 from Morpho
2. swap this USDC into oSQTH

**swap: price go down**

1. swap oSQTH into USDC = delta_amount1
2. use this USDC to repay on Morpho pool

## Put like wstETH option using V4 + oSQTH + Morpho hooks

### Hook Flow

weight = 50%
cRatio = 50%

**deposit USDC**

1. provide 50% of USDC into liquidity range [current_price/priceScalingFactor, current_price]
2. collateral 50% of USDC on Morpho pool

**withdraw USDC**

1. close uniswap position into wstETH and USDC 
2. calculate amounts to repay on Morpho pool (target_wstETH) and Squeeth (target_oSQTH) 
3. insure balance of oSQTH = target_oSQTH
4. burn oSQTH position and get ETH collateral back
5. swap all ETH into USDC
6. insure balance of wstETH = target_wstETH
7. repay borrow on Morpho using wstETH
8. withdraw USDC from Morpho and transfer all wstETH to user

**swap: price go down**

1. borrow wstETH = delta_amount0 from Morpho
2. swap wstETH into ETH
3. provide this ETH into collateral on Squeeth
4. mint oSQTH using cRatio percent of new collateral added 
5. swap all new oSQTH into USDC

**swap: price go up**

1. swap USDC = delta_amount1 into oSQTH
2. burn oSQTH position and get cRatio percent of collateral back
3. swap ETH into wstETH
4. repay on Morpho pool using this wstETH



## Setting up

#### Testing

Test all project
```
make test_all
```

Test call option
```
make test_call
```

or put option
```
make test_put
```

## Loyalty program using Brevis 
You could go into the `brevisCircuit` folder to deploy, test and use the Brevis circuit contract on Sepolia testnet.