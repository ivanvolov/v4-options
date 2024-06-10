// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IBrevisRequest {
    function sendRequest(bytes32 _requestId, address _refundee, address _callback) external payable;
}
