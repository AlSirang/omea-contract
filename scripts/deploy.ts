import { ethers } from "hardhat";

async function main() {
  const BUSD = await ethers.getContractFactory("BUSD");
  const busd = await BUSD.deploy();

  // const OMEA = await ethers.getContractFactory("OMEA");
  // const omea = await OMEA.deploy(
  //   "0x008ebfc38a0260187057ba5bc26d37dc797e791f",
  //   "0x008ebfc38a0260187057ba5bc26d37dc797e791f",
  //   busd.address
  // );

  // await omea.launchContract();
  console.log(`deployed to ${busd.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
