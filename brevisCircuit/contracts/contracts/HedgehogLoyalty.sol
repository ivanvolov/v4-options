// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./lib/BrevisApp.sol";
import "./lib/IBrevisProof.sol";

contract HedgehogLoyalty is BrevisApp, Ownable {
    event HedgehogLoyaltyAttested(address account, uint64 blockNum);

    bytes32 public vkHash;

    mapping(address => uint64) public isLoyal;

    constructor(address brevisProof) BrevisApp(IBrevisProof(brevisProof)) Ownable(msg.sender) {}

    function handleProofResult(
        bytes32 /*_requestId*/,
        bytes32 _vkHash,
        bytes calldata _circuitOutput
    ) internal override {
        require(vkHash == _vkHash, "invalid vk");

        (address txFrom, uint64 blockNum) = decodeOutput(_circuitOutput);

        isLoyal[txFrom] = blockNum; // This will help to setup the loyalty based on order of first usage if needed

        emit HedgehogLoyaltyAttested(txFrom, blockNum);
    }

    function decodeOutput(bytes calldata o) internal pure returns (address, uint64) {
        address txFrom = address(bytes20(o[0:20])); // txFrom was output as an address
        uint64 blockNum = uint64(bytes8(o[20:28])); // blockNum was output as a uint64 (8 bytes)
        return (txFrom, blockNum);
    }

    function setVkHash(bytes32 _vkHash) external onlyOwner {
        vkHash = _vkHash;
    }
}
