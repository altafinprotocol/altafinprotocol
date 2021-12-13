const { AbiCoder } = require("@ethersproject/abi");
const { expect } = require("chai");
const hre = require("hardhat");
const { BN, expectEvent, expectRevert, constants } = require('@openzeppelin/test-helpers');
const NAME = 'Altafin';
const SYMBOL = 'AFN';

var chai = require('chai');
var assert = chai.assert;

describe("Altafin", accounts => {

    let Altafin;
    let owner, alice, bob, addrs;
    const TOTAL_SUPPLY = new BN('100000000000000000000000');

    // Run only once before all tests
    before(async function () {

        [owner, alice, bob, ...addrs] = await ethers.getSigners();


        const AltafinFactory = await ethers.getContractFactory("Altafin");
        Altafin = await AltafinFactory.deploy();
        await Altafin.init(NAME, SYMBOL, TOTAL_SUPPLY.toString());

        let net = hre.network.config.chainId.toString();

        console.log(JSON.stringify({
            [net]: {
                "Altafin": Altafin.address,
            }
        }, null, 1));       
    });

    describe("Altafin Tests", accounts => {

        it("Should deploy contracts", async function () {
            expect(true).to.equal(true);
        });

        it('retrieve returns a value previously stored', async function () {
            const totalSupplyRead = await Altafin.totalSupply();
            const totalSupplyInput = TOTAL_SUPPLY.toString();
            expect(totalSupplyRead.eq(totalSupplyInput));
        });

        it('has a name', async function () {
            expect(await Altafin.name()).to.be.equal(NAME);
        });

        it('has a symbol', async function () {
            expect(await Altafin.symbol()).to.be.equal(SYMBOL);
        });

        it('assigns the initial total supply to the creator', async function () {
            const totalSupply = await Altafin.totalSupply();
            const ownerBalance = await Altafin.balanceOf(owner.address);
            expect(ownerBalance.eq(totalSupply));
        });

    });

    describe("Minting", accounts => {
        it("Can mint tokens increasing the receiver's balance and total supply as much", async() => {
            let balanceAlice = 0;
            balanceAlice = await Altafin.balanceOf(alice.address);
            console.debug("Alice's balance = %s", balanceAlice);

            let totalSupply = 0;
            totalSupply = await Altafin.totalSupply();
            console.debug("totalSupply = %s", totalSupply);

            let amt = '100';
            await Altafin.mint(alice.address, amt);

            let balanceAliceAfter = await Altafin.balanceOf(alice.address);
            console.debug("after mint Alice's balance = %s", balanceAliceAfter);

            let totalSupplyAfter = await Altafin.totalSupply();
            console.debug("after mint totalSupply = %s", totalSupplyAfter);

            let deltaAlice = balanceAliceAfter - balanceAlice;
            let deltaTotalSupply = totalSupplyAfter - totalSupply;

            expect(deltaAlice === amt);
            expect(deltaTotalSupply === amt);
        });
        // Add more individual tests later
    });

    describe("Burning", accounts => {
        it("Can Burn tokens reducing total supply",  async() => {
            let totalSupply =  await Altafin.totalSupply();
            let amt = '500';
            await Altafin.burn(amt);
            let totalSupplyAfter = await Altafin.totalSupply();
            console.debug("after burn totalSupply = %s", totalSupplyAfter);
            let deltaTotalSupply = totalSupply - totalSupplyAfter;
            expect(deltaTotalSupply === amt);
        });
    });

    describe("Pause/Unpause", accounts => {
        it("Check can Pause", async() => {
            let paused = await Altafin.paused();
            console.debug("Paused:%s", paused);
            await Altafin.pause();
            paused = await Altafin.paused();
            console.debug("Paused:%s", paused);
            assert.isTrue(paused);
        });
        it("Check can Unpause", async() => {
            let paused = await Altafin.paused();
            console.debug("Paused:%s", paused);
            await Altafin.unpause();
            paused = await Altafin.paused();
            console.debug("Paused:%s", paused);
            assert.isFalse(paused);
        });
        // Add more individual tests later
        // for example, transfer should fail when contract is paused
    });

    describe("Transfer", () => {
        it("Can transfer decreasing sender's balance and increasing recipient's balance as much.", async() => {
            let sender = 0, recipient = 0, delta = 0;
            let senderBal1 = 0, senderBal2 = 0;
            let recipientBal1 = 0, recipientBal2 = 0;
            recipient = bob.address;
            sender = Altafin.address;

            senderBal1 = await Altafin.balanceOf(sender);
            recipientBal1 = await Altafin.balanceOf(recipient);

            console.debug("recipientBal1:%s", recipientBal1);

            delta = 10;
            await Altafin.transfer(recipient, delta);

            senderBal2 = await Altafin.balanceOf(sender);
            recipientBal2 = await Altafin.balanceOf(recipient);

            console.debug("recipientBal2:%s", recipientBal2);
            let diff = recipientBal2 - recipientBal1;
            expect(diff === delta);
        });
    });

});
