// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {OptionBaseLib} from "../src/libraries/OptionBaseLib.sol";

contract OptionBaseLibTest is Test {
    address WETH;
    address WSTETH;
    address USDC;
    address OSQTH;

    function setUp() public {
        WETH = OptionBaseLib.WETH;
        vm.label(WETH, "WETH");
        WSTETH = OptionBaseLib.WSTETH;
        vm.label(WSTETH, "WSTETH");
        USDC = OptionBaseLib.USDC;
        vm.label(USDC, "USDC");
        OSQTH = OptionBaseLib.OSQTH;
        vm.label(OSQTH, "OSQTH");
    }

    function test_getFee() public view {
        assertEq(
            OptionBaseLib.getFee(WSTETH, USDC),
            OptionBaseLib.WSTETH_USDC_POOL_FEE
        );
        assertEq(
            OptionBaseLib.getFee(USDC, WSTETH),
            OptionBaseLib.WSTETH_USDC_POOL_FEE
        );

        assertEq(
            OptionBaseLib.getFee(WSTETH, WETH),
            OptionBaseLib.WSTETH_ETH_POOL_FEE
        );
        assertEq(
            OptionBaseLib.getFee(WETH, WSTETH),
            OptionBaseLib.WSTETH_ETH_POOL_FEE
        );

        assertEq(
            OptionBaseLib.getFee(USDC, WETH),
            OptionBaseLib.ETH_USDC_POOL_FEE
        );
        assertEq(
            OptionBaseLib.getFee(WETH, USDC),
            OptionBaseLib.ETH_USDC_POOL_FEE
        );

        assertEq(
            OptionBaseLib.getFee(WETH, OSQTH),
            OptionBaseLib.ETH_OSQTH_POOL_FEE
        );
        assertEq(
            OptionBaseLib.getFee(OSQTH, WETH),
            OptionBaseLib.ETH_OSQTH_POOL_FEE
        );
    }
}
