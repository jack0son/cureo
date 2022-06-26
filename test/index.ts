"use strict";

import * as chai from "chai";

import {
  defaultAbiCoder,
  formatBytes32String,
  keccak256,
  getCreate2Address,
  toUtf8Bytes,
  id,
} from "ethers/lib/utils";
import { Contract } from "typechain";

const { deployContract, MockProvider, solidity } = require("ethereum-waffle");
chai.use(solidity);
const { expect } = chai;

const CureoExhibition = require("../artifacts/contracts/Exhibition.sol/CureoExhibition.json");
const OfferController = require("../artifacts/contracts/Exhibition.sol/OfferController.json");
const NFT = require("../artifacts/contracts/Ownable.sol/Ownable.json");

const ETH = 1e6;
// const getRandomInt = (max: number) => Math.floor(Math.random() * max);
// const getRandomID = () => id(getRandomInt(1e6).toString());

describe("CureoExhibition", () => {
  const [curatorWallet, nftAdmin, sellerWallet] = new MockProvider().getWallets();

  let exhibitionContract: any;
  let nftContract: any;

  beforeEach(async () => {
    exhibitionContract = await deployContract(curatorWallet, CureoExhibition);
    nftContract = await deployContract(nftAdmin, CureoExhibition);

    // await token.connect(curatorWallet).deposit({ value: 1e9 });
  });

  describe("exhibtion contract", () => {
    it("should generate offer address", async () => {
      // const entropy = getRandomID();
      // const salt = formatBytes32String(entropy.toString());
      const salt = formatBytes32String("1");

      const sellerAddress = sellerWallet.address;
      const tokenAddress = nftContract.address;
      const tokenID = 12412;
      const price = 5 * ETH;

      const expectedOfferAddress = getCreate2Address(
        exhibitionContract.address,
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

      const offerAddress = await exhibitionContract.offerAddress(
        salt,
        sellerAddress,
        tokenAddress,
        tokenID,
        price
      );

      expect(offerAddress).to.be.equal(expectedOfferAddress);
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
