"use strict";

import * as chai from "chai";

import {
  defaultAbiCoder,
  formatBytes32String,
  keccak256,
  getCreate2Address,
  toUtf8Bytes,
  formatEther,
} from "ethers/lib/utils";
import { Contract } from "typechain";
import { BigNumberish } from "ethers";

const { deployContract, MockProvider, solidity } = require("ethereum-waffle");
chai.use(solidity);
const { expect } = chai;

const CureoExhibition = require("../artifacts/contracts/Exhibition.sol/CureoExhibition.json");
const OfferController = require("../artifacts/contracts/Exhibition.sol/OfferController.json");
const NFT = require("../artifacts/contracts/NFT.sol/NFT.json");

const ethStr = (val: BigNumberish) => `${formatEther(val)} ETH`;

const ETH = 1e6;
// const getRandomInt = (max: number) => Math.floor(Math.random() * max);
// const getRandomID = () => id(getRandomInt(1e6).toString());

const calculateOfferAddress = (
  exhibitionContractAddress: string,
  salt: string,
  sellerAddress: string,
  tokenAddress: string,
  tokenID: number,
  price: number
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

describe("CureoExhibition", () => {
  const [curatorWallet, nftAdmin, sellerWallet, buyerWallet] =
    new MockProvider().getWallets();

  let exhibitionInstance: any;
  let nftInstance: any;

  beforeEach(async () => {
    exhibitionInstance = await deployContract(curatorWallet, CureoExhibition);
    nftInstance = await deployContract(nftAdmin, NFT);

    // await token.connect(curatorWallet).deposit({ value: 1e9 });
  });

  describe("exhibition contract", () => {
    it("should generate offer address", async () => {
      // const entropy = getRandomID();
      // const salt = formatBytes32String(entropy.toString());
      const salt = formatBytes32String("1");

      const sellerAddress = sellerWallet.address;
      const tokenAddress = nftInstance.address;
      const tokenID = 12412;
      const price = 5 * ETH;

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
  });

  it("buyer should be able to purchase the nft", async () => {
    // const entropy = getRandomID();
    // const salt = formatBytes32String(entropy.toString());
    const salt = formatBytes32String("1");

    const sellerAddress = sellerWallet.address;
    const tokenAddress = nftInstance.address;
    const tokenID = 12412;
    const price = 5 * ETH;

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

    console.log(`Accepting exhibition offer at ${offerAddress}`);

    // accept the exhibition offer (seller)
    await nftInstance
      .connect(nftAdmin)
      .transferFrom(sellerAddress, offerAddress, tokenID);

    const sellerInitialBalance = await sellerWallet.getBalance();
    console.log(
      `Seller's initial balance: ${ethStr(sellerInitialBalance.toString())}`
    );
    console.log(`Purchasing offer at ${offerAddress}`);

    // purchase nft (buyer)
    await exhibitionInstance
      .connect(buyerWallet)
      .buy(salt, sellerAddress, tokenAddress, tokenID, price, {
        value: price,
        gasLimit: 1000000,
      });

    const owner = nftInstance.ownerOf(tokenID);
    expect(owner).to.equal(buyerWallet.address);

    const sellerNewBalance = await sellerWallet.getBalance();
    const diff = sellerNewBalance.sub(sellerInitialBalance);
    console.log(`Seller's new balance: ${ethStr(sellerNewBalance.toString())}`);
    console.log(`Difference ${ethStr(diff)}`);
  });

  it("seller should be able to refund the nft", async () => {
    // const entropy = getRandomID();
    // const salt = formatBytes32String(entropy.toString());
    const salt = formatBytes32String("1");

    const sellerAddress = sellerWallet.address;
    const tokenAddress = nftInstance.address;
    const tokenID = 12412;
    const price = 5 * ETH;

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

    console.log(`Accepting exhibition offer at ${offerAddress}`);

    // accept the exhibition offer (seller)
    await nftInstance
      .connect(nftAdmin)
      .transferFrom(sellerAddress, offerAddress, tokenID);

    console.log(`Refunding offer at ${offerAddress}`);

    // refund the nft (seller)
    await exhibitionInstance
      .connect(buyerWallet)
      .refund(salt, sellerAddress, tokenAddress, tokenID, price, {
        gasLimit: 1000000,
      });

    const owner = nftInstance.ownerOf(tokenID);
    expect(owner).to.equal(sellerWallet.address);
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
