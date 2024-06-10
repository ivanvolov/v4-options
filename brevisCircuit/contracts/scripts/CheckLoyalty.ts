import * as dotenv from 'dotenv';
import { ethers } from 'hardhat';

dotenv.config();

const deployContractAddress = '0x42daAF60a732F1Bb65272B03274a103a3d2e1306';
const targetAddress = '0xE652150aBCb929c04e013Fcb9889ce2160e14982';

const mainScript = async () => {
  const HedgehogLoyalty = await ethers.getContractAt('HedgehogLoyalty', deployContractAddress);

  const loyalty = await HedgehogLoyalty.isLoyal(targetAddress);
  console.log(`The Loyalty of target address ${targetAddress} is ${loyalty}`);
};

mainScript().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
