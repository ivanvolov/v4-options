// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

interface IHedgehogLoyaltyMock {
    function isLoyal(address user) external view returns (uint64);
}
