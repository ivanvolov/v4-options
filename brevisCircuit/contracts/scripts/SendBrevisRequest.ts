import * as dotenv from 'dotenv';
import { ethers } from 'hardhat';

dotenv.config();

const deployContractAddress = '0x5fB46FF3565a78bCC83F8394AC72933503b704FA';
const requestId = '0x2d057d9ed09b8ab05a6c29bb29b7d0bc64e743956da5d5bdc87acb727e871aa1';
const _callback = '0x42daAF60a732F1Bb65272B03274a103a3d2e1306';

const mainScript = async () => {
  const BrevisRequest = await ethers.getContractAt('IBrevisRequest', deployContractAddress);

  try {
    const refundee = '0x58b529F9084D7eAA598EB3477Fe36064C5B7bbC1';
    const tx = await BrevisRequest.sendRequest(requestId, refundee, _callback);
    console.log(`sendRequest tx hash: ${tx.hash}`);
    await tx.wait();
  } catch (error) {
    console.error(`Error calling setVkHash:`, error);
  }
};

mainScript().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
