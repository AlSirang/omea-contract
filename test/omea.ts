import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { expect, use as chaiUse } from "chai";
import chaiAsPromised from "chai-as-promised";
import { BigNumberish } from "ethers";
import { ethers } from "hardhat";
import { BUSD, OMEA } from "../typechain-types";

const toWei = (number: string) => ethers.utils.parseEther(number);
const fromWei = (number: BigNumberish) => ethers.utils.formatEther(number);

describe("OMEA", function () {
  let omea: OMEA;
  let busd: BUSD;
  let accounts: SignerWithAddress[];
  let deployer: SignerWithAddress;
  let devWallet: SignerWithAddress;
  let marketingWallet: SignerWithAddress;
  let stakeholder1: SignerWithAddress;
  let stakeholder2: SignerWithAddress;
  let stakeholder3: SignerWithAddress;

  const DISTRIBUTIONS = toWei("1000");
  const TOKENS_1000 = toWei("100");

  const DEV_FEE = 200; // 200 : 2 %. 10000 : 100 %
  const MARKETING_FEE = 200; // 200 : 2 %. 10000 : 100 %
  const PRINCIPAL_FEE = 100; // 100 : 1%. 10000 : 100 %

  const getBlockTimestamp = async () => {
    const blockNumBefore = await ethers.provider.getBlockNumber();
    const blockBefore = await ethers.provider.getBlock(blockNumBefore);
    return blockBefore.timestamp;
  };

  const get_dev_marketing_and_deposit = (deposit: BigNumberish) => {
    //@ts-ignore
    const devFee = deposit.mul(DEV_FEE).div(10000);
    //@ts-ignore
    const marketingFee = deposit.mul(MARKETING_FEE).div(10000);

    //@ts-ignore
    const finalDeposit = deposit.sub(devFee.add(marketingFee));

    return { devFee, marketingFee, finalDeposit };
  };

  // deploy BUSD
  const deployAndDistributeERC20Tokens = async () => {
    const _BUSD = await ethers.getContractFactory("BUSD");
    busd = await _BUSD.deploy();

    await busd.transfer(stakeholder1.address, DISTRIBUTIONS);
    await busd.transfer(stakeholder2.address, DISTRIBUTIONS);
    await busd.transfer(stakeholder3.address, DISTRIBUTIONS);
  };

  // deploy OMEA
  beforeEach(async () => {
    accounts = await ethers.getSigners();

    deployer = accounts[0];
    devWallet = accounts[1];
    marketingWallet = accounts[2];
    stakeholder1 = accounts[3];
    stakeholder2 = accounts[4];
    stakeholder3 = accounts[5];

    await deployAndDistributeERC20Tokens();
    const OMEA = await ethers.getContractFactory("OMEA");
    omea = await OMEA.deploy(
      devWallet.address,
      marketingWallet.address,
      busd.address
    );

    await omea.launchContract();

    // set max allowance
    await busd.connect(stakeholder1).approve(omea.address, DISTRIBUTIONS);
    await busd.connect(stakeholder2).approve(omea.address, DISTRIBUTIONS);
    await busd.connect(stakeholder3).approve(omea.address, DISTRIBUTIONS);
  });

  describe("Deposit", function () {
    beforeEach(async function () {
      await omea
        .connect(stakeholder1)
        .deposit(TOKENS_1000, stakeholder1.address);
    });

    it("should update deposits", async () => {
      const depositsOf = await omea.depositsOf(stakeholder1.address);
      expect(depositsOf.length).to.eq(1);
    });

    it("should update investors count", async () => {
      const { totalInvestors } = await omea.getInvestmentInfo();
      expect(totalInvestors).to.eq(1);
    });

    it("should update total Depoists", async () => {
      const { totalValueLocked } = await omea.getInvestmentInfo();

      expect(totalValueLocked).to.eq(TOKENS_1000);
    });

    it("should update total invested amount of investor", async () => {
      const { finalDeposit } = get_dev_marketing_and_deposit(TOKENS_1000);

      const investorInfo = await omea.investors(stakeholder1.address);
      expect(investorInfo.totalInvested).to.eq(finalDeposit);
    });

    it("should update claimable rewards on next deposit", async () => {
      const { finalDeposit } = get_dev_marketing_and_deposit(TOKENS_1000);

      const HPR = await omea.getHPR(finalDeposit);
      const rewards = (finalDeposit * HPR * (3600 / 3600)) / 10000;

      const nextBlockStamp = (await getBlockTimestamp()) + 3600;
      await time.increaseTo(nextBlockStamp);
      await omea
        .connect(stakeholder1)
        .deposit(toWei("100"), stakeholder1.address);

      const investorInfo = await omea.investors(stakeholder1.address);

      expect(investorInfo.claimableAmount).to.eq(rewards.toString());
    });

    it("should add referrer to list", async () => {
      await omea
        .connect(stakeholder1)
        .deposit(TOKENS_1000, stakeholder2.address);

      const referrer = await omea.investors(stakeholder2.address);
      const investorInfo = await omea.investors(stakeholder1.address);

      expect(referrer.referrals).to.eq("1");
      expect(investorInfo.referrer).to.eq(stakeholder2.address);
    });
  });

  describe("Bonus", () => {
    beforeEach(async function () {
      await omea
        .connect(stakeholder1)
        .deposit(TOKENS_1000, stakeholder1.address);

      const nextBlockStamp = (await getBlockTimestamp()) + 3600;
      await time.increaseTo(nextBlockStamp);
      await omea.addBonus(stakeholder1.address, toWei("4"));
    });

    it("should add bonus", async () => {
      const investorInfo = await omea.investors(stakeholder1.address);
      expect(investorInfo.bonus).to.eq(toWei("4"));
    });

    it("should calculate claimable rewards for initial deposit", async () => {
      const { finalDeposit } = get_dev_marketing_and_deposit(TOKENS_1000);

      const nextBlockStamp = (await getBlockTimestamp()) + 3600;
      await time.increaseTo(nextBlockStamp);

      const HPR = await omea.getHPR(finalDeposit);

      const firstHour = finalDeposit.mul(HPR).div(10000);
      const secondHour = TOKENS_1000.mul(HPR).div(10000);
      const total = firstHour.add(secondHour);

      const claimables = await omea.getClaimableAmount(stakeholder1.address);
      expect(claimables).to.eq(total);
    });

    it("should revert for more than 1000 bonus", async () => {
      await expect(
        omea.addBonus(stakeholder1.address, toWei("996"))
      ).to.revertedWith("Bonus limit reached");
    });
  });

  describe("capital withdraw", () => {
    before(async () => {
      await omea
        .connect(stakeholder1)
        .deposit(TOKENS_1000, stakeholder1.address);
    });
  });

  describe("Get Claimable info after rewards claim", () => {
    beforeEach(async function () {
      await omea
        .connect(stakeholder1)
        .deposit(TOKENS_1000, stakeholder1.address);
    });

    it("should give correct values on getClaimable amount", async () => {
      const nextBlockStamp = (await getBlockTimestamp()) + 3600;
      await time.increaseTo(nextBlockStamp);

      await omea.connect(stakeholder1).claimAllReward();
      const nextBlockStamp2 = (await getBlockTimestamp()) + 3600;
      await time.increaseTo(nextBlockStamp2);
      const claimables2 = await omea.getClaimableAmount(stakeholder1.address);
    });
  });
  // CONSTANTS CHECK
  describe("HRP LIMITS,", () => {
    const ZERO_DEPOSIT = toWei("0");
    const HPR_1_UPPER_LIMIT = toWei("100");
    const HPR_2_LOWER_LIMIT = toWei("101");
    const HPR_2_UPPER_LIMIT = toWei("500");
    const HPR_3_LOWER_LIMIT = toWei("501");
    const HPR_3_UPPER_LIMIT = toWei("1000");
    const HPR_4_LOWER_LIMIT = toWei("1001");
    const HPR_4_UPPER_LIMIT = toWei("5000");
    const HPR_5_LOWER_LIMIT = toWei("5001");
    const HPR_5_UPPER_LIMIT = toWei("6000");

    it("should return 0 HPR for no deposit", async () => {
      expect(await omea.getHPR(ZERO_DEPOSIT)).to.eq(0);
    });
    it("should return correct HPR_1 for deposit", async () => {
      expect(await omea.getHPR(HPR_1_UPPER_LIMIT)).to.eq(7);
    });

    it("should return correct HPR_2 for deposit", async () => {
      expect(await omea.getHPR(HPR_2_UPPER_LIMIT)).to.eq(8);
      expect(await omea.getHPR(HPR_2_LOWER_LIMIT)).to.eq(8);
    });
    it("should return correct HPR_3 for deposit", async () => {
      expect(await omea.getHPR(HPR_3_UPPER_LIMIT)).to.eq(10);
      expect(await omea.getHPR(HPR_3_LOWER_LIMIT)).to.eq(10);
    });

    it("should return correct HPR_4 for deposit", async () => {
      expect(await omea.getHPR(HPR_4_UPPER_LIMIT)).to.eq(12);
      expect(await omea.getHPR(HPR_4_LOWER_LIMIT)).to.eq(12);
    });
    it("should return correct HPR_5 for deposit", async () => {
      expect(await omea.getHPR(HPR_5_UPPER_LIMIT)).to.eq(15);
      expect(await omea.getHPR(HPR_5_LOWER_LIMIT)).to.eq(15);
    });
  });
});
