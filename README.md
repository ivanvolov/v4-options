# Call wstETH using V4 + oSQTH + Morpho hooks

### Hooks Flow

**depositETH**

1. mint 50% of wstETH into liquidity in range [current_price, current_price*2]
2. collateral 50% of wstETH on Morpho pool

**withdrawETH**

1. close uniswap position into wstETH and USDC 
2. repay borrow on Morpho using USDC (extra usdc could be bought with wstETH)
3. withdraw wstETH from Morpho and transfer to user
4. sell remaining USDC into wstETH

**swap: price go down**

1. sell oSQTH into USDC = delta_amount1
2. use this USDC to repay on Morpho pool