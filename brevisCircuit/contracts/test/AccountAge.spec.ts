import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { HedgehogLoyalty__factory, MockBrevisProof__factory } from '../typechain';

const vkHash = '0x8888888888888888888888888888888888888888888888888888888888888888';

async function deployHedgehogLoyaltyFixture() {
  const [owner, otherAccount] = await ethers.getSigners();
  const MockBrevisProof = (await ethers.getContractFactory('MockBrevisProof')) as MockBrevisProof__factory;
  const mockBrevisProof = await MockBrevisProof.deploy();

  const HedgehogLoyalty = (await ethers.getContractFactory('HedgehogLoyalty')) as HedgehogLoyalty__factory;
  const hedgehogLoyalty = await HedgehogLoyalty.deploy(mockBrevisProof.getAddress());
  await hedgehogLoyalty.setVkHash(vkHash);

  return { hedgehogLoyalty, mockBrevisProof, owner };
}

describe('Account age', async () => {
  it('should handle proof result in callback', async () => {
    const { hedgehogLoyalty, mockBrevisProof, owner } = await loadFixture(deployHedgehogLoyaltyFixture);

    const abiCoder = ethers.AbiCoder.defaultAbiCoder();

    // Generating some test data
    // In guest circuit we have:
    // api.OutputAddress(tx.From)
    // api.OutputUint(64, tx.BlockNum)
    // Thus, in practice Brevis would call our contract with abi.encodePacked(address, uint64)
    // requestId doesn't matter here as we don't use it
    const requestId = '0x0000000000000000000000000000000000000000000000000000000000000000';
    const expectedAccount = '0x1234567812345678123456781234567812345678';
    const expectedBlockNum = 12345678;

    const testCircuitOutput = ethers.solidityPacked(['address', 'uint64'], [expectedAccount, expectedBlockNum]);
    const testOutputCommit = ethers.keccak256(testCircuitOutput);

    await mockBrevisProof.setMockOutput(requestId, testOutputCommit, vkHash);

    const tx = await hedgehogLoyalty.brevisCallback(requestId, testCircuitOutput);
    await expect(tx).to.emit(hedgehogLoyalty, 'HedgehogLoyaltyAttested').withArgs(expectedAccount, expectedBlockNum);
  });
});
