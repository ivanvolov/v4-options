import * as dotenv from 'dotenv';
import { ethers } from 'hardhat';

dotenv.config();

const deployContractAddress = '0x42daAF60a732F1Bb65272B03274a103a3d2e1306';
const vkHash = '0x0be2f0142e8d8457cfbe8d1a8a3ec59e9636c64e476839c26d9b2283fbeef35c';

const mainScript = async () => {
  const HedgehogLoyalty = await ethers.getContractAt('HedgehogLoyalty', deployContractAddress);

  try {
    const tx = await HedgehogLoyalty.setVkHash(vkHash);
    console.log(`setVkHash tx hash: ${tx.hash}`);
    await tx.wait();
  } catch (error) {
    console.error(`Error calling setVkHash:`, error);
  }
};

mainScript().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
