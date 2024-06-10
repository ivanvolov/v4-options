// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

contract HedgehogLoyaltyMock {
    mapping(address => uint64) public isLoyal;

    function setIsLoyal(address user, uint64 value) external {
        isLoyal[user] = value;
    }
}
