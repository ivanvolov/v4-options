// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {OptionBaseLib} from "../../src/libraries/OptionBaseLib.sol";

abstract contract OptionTestBase {
    function getETH_OSQTHPriceV3() public view returns (uint256) {
        return
            OptionBaseLib.getV3PoolPrice(
                0x82c427AdFDf2d245Ec51D8046b41c4ee87F0d29C
            );
    }

    function getETH_USDCPriceV3() public view returns (uint256) {
        return
            OptionBaseLib.getV3PoolPrice(
                0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640
            );
    }
}
