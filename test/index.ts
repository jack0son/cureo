"use strict";

import * as chai from "chai";

import {
  defaultAbiCoder,
  formatBytes32String,
  keccak256,
  getCreate2Address,
  toUtf8Bytes,
  formatEther,
  parseEther,
} from "ethers/lib/utils";
import { BigNumber, BigNumberish } from "ethers";
const NFT = require("../artifacts/contracts/NFT.sol/NFT.json");
const CureoExhibition = require("../artifacts/contracts/Exhibition.sol/CureoExhibition.json");
const OfferController = require("../artifacts/contracts/Exhibition.sol/OfferController.json");
// const hardhat = require("hardhat");

const { deployContract, MockProvider, solidity } = require("ethereum-waffle");
chai.use(solidity);
const { expect } = chai;

const ethStr = (val: BigNumberish) => `${formatEther(val)} ETH`;
const DAY = 60 * 60 * 24;

// Entropy:
// const getRandomInt = (max: number) => Math.floor(Math.random() * max);
// const getRandomID = () => id(getRandomInt(1e6).toString());

const calculateOfferAddress = (
  exhibitionContractAddress: string,
  salt: string,
  sellerAddress: string,
  tokenAddress: string,
  tokenID: BigNumberish,
  price: BigNumberish
): string =>
  getCreate2Address(
    exhibitionContractAddress,
    keccak256(
      defaultAbiCoder.encode(
        ["bytes32", "bytes32", "address", "address", "uint256", "uint256"],
        [
          keccak256(toUtf8Bytes("fixed-offer")),
          salt,
          sellerAddress,
          tokenAddress,
          tokenID,
          price,
        ]
      )
    ),
    keccak256(OfferController.bytecode)
  );

const defaultGasLimit = 1000000;
const defaultStartFuture = DAY;

describe("CureoExhibition", () => {
  const provider = new MockProvider();
  const [curatorWallet, nftAdmin, sellerWallet, buyerWallet] =
    provider.getWallets();

  let exhibitionInstance: any;
  let nftInstance: any;

  async function getBlockTime(): Promise<number> {
    const bn = await provider.getBlockNumber();
    const block = await provider.getBlock(bn);
    return block.timestamp;
  }

  async function elapseTime(time: number) {
    const now = await getBlockTime();
    await provider.send("evm_setNextBlockTimestamp", [now + time]);
    await provider.send("evm_mine");
  }

  const deployContracts = async (
    commission: number,
    startTime: number,
    salePeriod: number
  ) => {
    if (startTime === 0) {
      console.log("USE DEFAULT");
      startTime = (await getBlockTime()) + defaultStartFuture;
    }

    exhibitionInstance = await deployContract(
      curatorWallet,
      CureoExhibition,
      [commission, startTime, salePeriod],
      { gasLimit: defaultGasLimit*6 }
    );
    nftInstance = await deployContract(nftAdmin, NFT);

    // const factory = await hardhat.ethers.getContractFactory("NFT");
    // const nftInstance = await factory.deploy();

    console.log("Waiting contracts deployed...");
    await Promise.all([exhibitionInstance.deployed(), nftInstance.deployed()]);
    console.log("DEPLOYED");
  };

  describe("exhibition contract basics", () => {
    beforeEach(async () => {
      await deployContracts(0, 0, DAY * 4);
    });

    it("should generate offer address", async () => {
      // const entropy = getRandomID();
      // const salt = formatBytes32String(entropy.toString());
      const salt = formatBytes32String("1");

      const sellerAddress = sellerWallet.address;
      const tokenAddress = nftInstance.address;
      const tokenID = 12412;
      const price = parseEther("5");

      await deployContracts(0, 0, 3*DAY);

      const expectedOfferAddress = calculateOfferAddress(
        exhibitionInstance.address,
        salt,
        sellerAddress,
        tokenAddress,
        tokenID,
        price
      );

      const offerAddress = await exhibitionInstance.offerAddress(
        salt,
        sellerAddress,
        tokenAddress,
        tokenID,
        price
      );

      expect(offerAddress).to.be.equal(expectedOfferAddress);
    });

    it("buyer should be able to purchase the nft", async () => {
      // const entropy = getRandomID();
      // const salt = formatBytes32String(entropy.toString());
      const salt = formatBytes32String("1");

      const sellerAddress = sellerWallet.address;
      const tokenAddress = nftInstance.address;
      const tokenID = 12412;
      const price = parseEther("5");

      // give seller a test nft
      await nftInstance.connect(nftAdmin).mint(sellerAddress, tokenID);

      // create offer (curator)
      const offerAddress = await exhibitionInstance.offerAddress(
        salt,
        sellerAddress,
        tokenAddress,
        tokenID,
        price
      );

      console.log(`NFT owner originally ${await nftInstance.ownerOf(tokenID)}`);
      console.log(`Accepting exhibition offer at ${offerAddress}`);

      // accept the exhibition offer (seller)
      let tx = await nftInstance
        .connect(sellerWallet)
        .transferFrom(sellerAddress, offerAddress, tokenID, {
          gasLimit: defaultGasLimit,
        });

      await tx.wait();

      console.log(
        `NFT owner after accepting ${await nftInstance.ownerOf(tokenID)}`
      );
      expect(await nftInstance.ownerOf(tokenID)).to.equal(offerAddress);

      const sellerInitialBalance = await sellerWallet.getBalance();
      console.log(
        `Seller's initial balance: ${ethStr(sellerInitialBalance.toString())}`
      );
      console.log(`Purchasing offer at ${offerAddress}`);

      // wait for sale start
      await elapseTime(defaultStartFuture);

      // purchase nft (buyer)
      tx = await exhibitionInstance
        .connect(buyerWallet)
        .buy(salt, sellerAddress, tokenAddress, tokenID, price, {
          value: price,
          gasLimit: 1000000,
        });

      await tx.wait();

      const owner = await nftInstance.ownerOf(tokenID);
      console.log(`NFT owner after buying ${owner}`);
      expect(owner).to.equal(buyerWallet.address);

      const sellerNewBalance = await sellerWallet.getBalance();
      const diff = sellerNewBalance.sub(sellerInitialBalance);
      console.log(
        `Seller's new balance: ${ethStr(sellerNewBalance.toString())}`
      );
      console.log(`Difference ${ethStr(diff)}`);

      // BigNumber comparison should pass but doesn't:
      //  expect(diff.eq(price)).to.be.true("seller received funds");
      // use string comparison instead
      expect(price.toString()).to.equal(diff.toString());
    });

    it("seller should be able to reclaim the nft if sale not started", async () => {
      // const entropy = getRandomID();
      // const salt = formatBytes32String(entropy.toString());
      const salt = formatBytes32String("1");

      const sellerAddress = sellerWallet.address;
      const tokenAddress = nftInstance.address;
      const tokenID = 12412;
      const price = parseEther("5");

      // give seller a test nft
      let tx = await nftInstance.connect(nftAdmin).mint(sellerAddress, tokenID);
      await tx.wait();

      // create offer (curator)
      const offerAddress = await exhibitionInstance.offerAddress(
        salt,
        sellerAddress,
        tokenAddress,
        tokenID,
        price
      );

      console.log(`Accepting exhibition offer at ${offerAddress}`);

      // accept the exhibition offer (seller)
      tx = await nftInstance
        .connect(sellerWallet)
        .transferFrom(sellerAddress, offerAddress, tokenID, {
          gasLimit: defaultGasLimit,
        });
      await tx.wait();

      console.log(`Refunding offer at ${offerAddress}`);

      // refund the nft (seller)
      tx = await exhibitionInstance
        .connect(buyerWallet)
        .refund(salt, sellerAddress, tokenAddress, tokenID, price, {
          gasLimit: 1000000,
        });
      await tx.wait();

      const owner = await nftInstance.ownerOf(tokenID);
      expect(owner).to.equal(sellerWallet.address);
    });
  });

  describe("exhibition contract parameterised", () => {
    it("cannot buy before sale opens", async () => {});

    it("curator should receive commission", async () => {
      const commissionPercent = 34;
      await deployContracts(commissionPercent, 0, DAY);
      // const entropy = getRandomID();
      // const salt = formatBytes32String(entropy.toString());
      const salt = formatBytes32String("1");

      const sellerAddress = sellerWallet.address;
      const tokenAddress = nftInstance.address;
      const tokenID = 12412;
      const price = parseEther("5");

      // give seller a test nft
      await nftInstance.connect(nftAdmin).mint(sellerAddress, tokenID);

      // create offer (curator)
      const offerAddress = await exhibitionInstance.offerAddress(
        salt,
        sellerAddress,
        tokenAddress,
        tokenID,
        price
      );

      console.log(`NFT owner originally ${await nftInstance.ownerOf(tokenID)}`);
      console.log(`Accepting exhibition offer at ${offerAddress}`);

      // accept the exhibition offer (seller)
      let tx = await nftInstance
        .connect(sellerWallet)
        .transferFrom(sellerAddress, offerAddress, tokenID, {
          gasLimit: defaultGasLimit,
        });

      await tx.wait();

      console.log(
        `NFT owner after accepting ${await nftInstance.ownerOf(tokenID)}`
      );
      expect(await nftInstance.ownerOf(tokenID)).to.equal(offerAddress);

      // wait for sale start
      await elapseTime(defaultStartFuture);

      const curatorInitialBalance = await curatorWallet.getBalance();
      console.log(
        `Curators's initial balance: ${ethStr(
          curatorInitialBalance.toString()
        )}`
      );
      console.log(`Purchasing offer at ${offerAddress}`);

      // purchase nft (buyer)
      tx = await exhibitionInstance
        .connect(buyerWallet)
        .buy(salt, sellerAddress, tokenAddress, tokenID, price, {
          value: price,
          gasLimit: 1000000,
        });

      await tx.wait();

      const owner = await nftInstance.ownerOf(tokenID);
      console.log(`NFT owner after buying ${owner}`);
      expect(owner).to.equal(buyerWallet.address);

      const curatorNewBalance = await curatorWallet.getBalance();
      const diff = curatorNewBalance.sub(curatorInitialBalance);
      console.log(
        `Curator's new balance: ${ethStr(curatorNewBalance.toString())}`
      );
      console.log(`Difference ${ethStr(diff)}`);

      const expectedCommission = price
        .mul(commissionPercent)
        .div(BigNumber.from(100));
      console.log(`Expected commission`, expectedCommission.toString());

      expect(expectedCommission.toString()).to.equal(diff.toString());
    });
  });
});

/*
describe("Greeter", function () {
  it("Should return the new greeting once it's changed", async function () {
    const Greeter = await ethers.getContractFactory("Greeter");
    const greeter = await Greeter.deploy("Hello, world!");
    await greeter.deployed();

    expect(await greeter.greet()).to.equal("Hello, world!");

    const setGreetingTx = await greeter.setGreeting("Hola, mundo!");

    // wait until the transaction is mined
    await setGreetingTx.wait();

    expect(await greeter.greet()).to.equal("Hola, mundo!");
  });
});

 */
