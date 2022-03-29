import { expect } from 'chai'
import { ethers } from 'hardhat'
import { BigNumberish } from 'ethers'
import { BigNumber } from '@ethersproject/bignumber'

import { usdcABI } from '../scripts/abi/usdc'
import { altaABI } from '../scripts/abi/alta'
import { Earn, EarnV2 } from '../typechain-types/contracts/Earn'
import { EarnV2__factory } from '../typechain-types/factories/contracts/Earn'
import hre from "hardhat"

// List of variables that are reused throughout the tests
const ALTA = "0xe0cCa86B254005889aC3a81e737f56a14f4A38F5"
const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
const LOAN_ADDRESS = "0xbdffbabfc682f4a800ebfba3ed147fd629fc8572"
const treasury = '0x087183a411770a645A96cf2e31fA69Ab89e22F5E'
const usdcWhale = '0xfc7470c14baef608dc316f5702790eefee9cc258'
const MAX_UINT = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
const ethWhale = '0x73BCEb1Cd57C711feaC4224D062b0F6ff338501e'
const usdcWhale2 = "0xaf10cc6c50defff901b535691550d7af208939c5"
const swapTarget: string = "0xdef1c0ded9bec7f1a1670819833240f027b25eff"
const swapCallData: string = "0x415565b0000000000000000000000000e0cca86b254005889ac3a81e737f56a14f4a38f5000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000000000000000000000000000056bc75e2d631000000000000000000000000000000000000000000000000000000000000001f1103600000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000036000000000000000000000000000000000000000000000000000000000000006c00000000000000000000000000000000000000000000000000000000000000015000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000e0cca86b254005889ac3a81e737f56a14f4a38f5000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000260000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000002400000000000000000000000000000000000000000000000056bc75e2d631000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000b446f646f5632000000000000000000000000000000000000000000000000000000000000000000056bc75e2d63100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000040000000000000000000000000811a11913b1d83b6b15febb7b1822627788c073900000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000150000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000002c000000000000000000000000000000000000000000000000000000000000002a0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000012556e6973776170563300000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000000000000001f11036000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000e592427a0aece92de3edee1f18e0157c058615640000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002bc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000064a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000003000000000000000000000000e0cca86b254005889ac3a81e737f56a14f4a38f5000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000931e8e6fad6243738f"
const accountToFund: string = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"
let earn: EarnV2
let time: number = 1095 // 1095 days = 3 years
let usdcRate: number = 500 // 500 = 5%
let altaRatio: number = 10000 // 10000 = 100%
let usdcMax: number = 31000000
let altaContract: any
let usdcContract: any
let deployer: any
let signer: any
let amount = "10000000000000000000000"


interface EarnContract {
    owner: string,
    startTime: BigNumber,
    contractLength: BigNumber,
    tokenAddress: string,
    tokenAmount: BigNumber,
    usdcPrincipal: BigNumber,
    usdcRate: BigNumber,
    usdcInterestPaid: BigNumber,
    altaAmount: BigNumber,
    usdcBonusRate: BigNumber,
    altaBonusAmount: BigNumber,
    status: number
}

describe("Earn", async () => {
    before(async () => {
        const Earn: EarnV2__factory = (await ethers.getContractFactory("EarnV2")) as EarnV2__factory
        earn = await Earn.deploy(USDC, ALTA, LOAN_ADDRESS, LOAN_ADDRESS)
        let signers = await ethers.getSigners()
        deployer = signers[0]
        altaContract = new ethers.Contract(ALTA, JSON.parse(altaABI), deployer)
        usdcContract = new ethers.Contract(USDC, JSON.parse(usdcABI), deployer)
    })

    beforeEach(async function () {


        await altaContract.connect(deployer).approve(earn.address, BigNumber.from(MAX_UINT))
        await altaContract.allowance(deployer.address, earn.address)
        await usdcContract.connect(deployer).approve(earn.address, BigNumber.from(MAX_UINT))
        await usdcContract.allowance(deployer.address, earn.address)

        await deployer.sendTransaction({
            to: treasury,
            value: ethers.utils.parseEther("1.0"), // Sends exactly 1.0 ether
        })

        await altaContract.approve(earn.address, MAX_UINT)

        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [treasury],
        })
        signer = await ethers.getSigner(treasury)
    })

    describe("Migration", async () => {
        it("should migrate all old contracts", async () => {
            const Earn = await ethers.getContractFactory("EarnV2")
            let earn = await Earn.deploy(USDC, ALTA, LOAN_ADDRESS, LOAN_ADDRESS)
            const EarnV1 = await ethers.getContractFactory("Earn")
            const earnV1 = EarnV1.attach("0x279493E1ED2F32FfDe533402969070539d3e926C")
            let oldContracts: EarnContract[] = []
            try {
                oldContracts = await earnV1.getAllEarnContracts()
            } catch (e) {
                oldContracts = []
            }

            let migratedContracts: {
                owner: string,
                startTime: BigNumberish,
                contractLength: BigNumberish,
                altaAmount: BigNumberish,
                usdcPrincipal: BigNumberish,
                usdcRate: BigNumberish,
                usdcInterestPaid: BigNumberish,
                altaRatio: BigNumberish,
                altaInterestPaid: BigNumberish,
                usdcBonusRate: BigNumberish,
                altaBonusRatio: BigNumberish,
                status: number
            }[] = []

            for (let i = 0; i < oldContracts.length; i++) {
                migratedContracts.push({
                    owner: oldContracts[i].owner, // owner
                    startTime: oldContracts[i].startTime, // startTime
                    contractLength: oldContracts[i].contractLength, // contractLength,
                    altaAmount: oldContracts[i].tokenAmount, // tokenAmount
                    usdcPrincipal: oldContracts[i].usdcPrincipal, // usdcPrincipal
                    usdcRate: oldContracts[i].usdcRate, // usdcRate
                    usdcInterestPaid: oldContracts[i].usdcInterestPaid, //usdcInterestPaid
                    altaRatio: 20000, // altaRatio
                    altaInterestPaid: 0,
                    usdcBonusRate: oldContracts[i].usdcBonusRate, // usdcBonusRate
                    altaBonusRatio: 40000, // altaBonusRatio
                    status: oldContracts[i].status // status
                })
            }
            await earn.migrateContracts(migratedContracts)

            let contract = await earn.getAllEarnContracts()
            expect(contract.length).to.equal(oldContracts.length)
        })
    })

    describe("ALTA", async () => {
        it("Should set a new ALTA address", async function () {
            let altaAddress = await earn.ALTA()
            expect(altaAddress).to.be.equal(ALTA)
            await earn.setAltaAddress(treasury)
            altaAddress = await earn.ALTA()
            expect(altaAddress).to.be.not.equal(ALTA)
            expect(altaAddress).to.be.equal(treasury)
            await earn.setAltaAddress(ALTA)
        })
    })

    describe("Pausable", async () => {
        it("Should not allow new contracts when paused", async function () {
            await earn.pause()

            let amount = "10000000000000000000000"
            await altaContract.connect(signer).transfer(accountToFund, amount)

            await earn.addTerm(time, usdcRate, altaRatio, usdcMax)
            expect(await earn.earnTerms(0)).to.be.not.null

            await expect(earn.openContract(0, 100, swapTarget, swapCallData)).to.be.revertedWith('Pausable: paused')
        })

        it("Should allow new contracts when unpaused", async function () {
            await earn.unpause()
            await expect(earn.openContract(0, 100, swapTarget, swapCallData)).to.not.be.revertedWith('Pausable: paused')
        })
    })

    describe("Earn Terms", async () => {
        it("Should return the earnTerm when it's added", async function () {
            await earn.addTerm(time, usdcRate, altaRatio, usdcMax)
            const earnTerm = await earn.earnTerms(1)

            expect(earnTerm).to.be.not.null
            expect(earnTerm.time).to.be.equal(time)
            expect(earnTerm.usdcRate).to.be.equal(usdcRate)
            expect(earnTerm.altaRatio).to.be.equal(altaRatio)
        })

        it("Should return the new earnTerm after it is updated", async function () {

            await earn.addTerm(time, usdcRate, altaRatio, usdcMax)
            let earnTerm = await earn.earnTerms(0)
            expect(earnTerm).to.be.not.null

            let usdcAccepted: BigNumber = earnTerm.usdcAccepted
            let open: boolean = earnTerm.open
            await earn.updateTerm(0, time, usdcRate, altaRatio, usdcMax, usdcAccepted, open)
            const earnTerms = await earn.getAllEarnTerms()
            expect(earnTerms.length).to.be.equal(3)
            earnTerm = await earn.earnTerms(2)

            expect(earnTerm).to.be.not.null
            expect(earnTerm.time).to.be.equal(time)
            expect(earnTerm.usdcRate).to.be.equal(usdcRate)
            expect(earnTerm.altaRatio).to.be.equal(altaRatio)
            expect(earnTerm.usdcMax).to.be.equal(usdcMax)
            expect(earnTerm.usdcAccepted).to.be.equal(usdcAccepted)
            expect(earnTerm.open).to.be.equal(open)
        })

        it("Should have multiple earnTerms in the array", async function () {

            await earn.addTerm(time, usdcRate, altaRatio, usdcMax)
            expect(await earn.earnTerms(3)).to.be.not.null

            await earn.addTerm(time, usdcRate, altaRatio, usdcMax)
            const earnTerms = await earn.getAllEarnTerms()
            expect(earnTerms.length).to.be.equal(5)
            expect(earnTerms[3]).to.be.not.null
            expect(earnTerms[4]).to.be.not.null
        })

        it("Should change status to closed when closeTerm is called", async function () {
            await earn.addTerm(time, usdcRate, altaRatio, usdcMax)
            expect(await earn.earnTerms(0)).to.be.not.null

            await earn.addTerm(time, usdcRate, altaRatio, usdcMax)
            let earnTerms = await earn.getAllEarnTerms()
            expect(earnTerms.length).to.be.equal(7)
            expect(earnTerms[5]).to.be.not.null
            expect(earnTerms[6]).to.be.not.null

            await earn.closeTerm(5)
            earnTerms = await earn.getAllEarnTerms()
            expect(earnTerms.length).to.be.equal(7)
            expect(earnTerms[5]).to.be.not.null
            expect(earnTerms[6]).to.be.not.null
            let earnTerm = await earn.earnTerms(5)
            expect(earnTerm.open).to.be.false
        })
    })

    describe("Earn Contracts", async () => {
        it("Should open contract with ALTA", async function () {
            await deployer.sendTransaction({
                to: treasury,
                value: ethers.utils.parseEther("1.0"), // Sends exactly 1.0 ether
            })

            let amount = "10000000000000000000000"
            await altaContract.connect(signer).transfer(accountToFund, amount)

            await earn.addTerm(time, usdcRate, altaRatio, usdcMax)
            expect(await earn.earnTerms(0)).to.be.not.null

            const openContract = await earn.openContract(0, amount, swapTarget, swapCallData)
            await openContract.wait()

            let earnContract = await earn.getAllEarnContracts()
            expect(earnContract.length).to.be.equal(1)

            // const usdcBalanceEarn = await usdcContract.balanceOf(earn.address)
            // const interestReserve = await earn.calculateInterestReserves(amount, usdcRate)
            // expect(usdcBalanceEarn).to.be.equal(interestReserve)

            // Test interest redemption
            await hre.network.provider.request({
                method: "hardhat_mine",
                params: ["0x1000"]
            })
            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale2],
            })
            let whale = await ethers.getSigner(usdcWhale2)
            await usdcContract.connect(whale).transfer(earn.address, "100000000000")
            await altaContract.connect(signer).transfer(earn.address, BigNumber.from(amount).mul(1000))
            let usdcBalanceBefore = await usdcContract.balanceOf(accountToFund)
            expect(await earn.redeemInterest(0)).to.not.Throw
            let usdcBalanceAfter = await usdcContract.balanceOf(accountToFund)
            expect(Number(usdcBalanceAfter)).to.be.greaterThan(Number(usdcBalanceBefore))

            // Test usdcAccepted update on earnTerm
            let earnTerms = await earn.getAllEarnTerms()
            expect(earnTerms.length).to.be.equal(8)
            let earnTerm = await earn.earnTerms(0)
            expect(earnTerm).to.be.not.null
            expect(earnTerm.usdcAccepted).to.be.gt(0)

            // Test if earnTerm is now closed
            expect(earnTerm.open).to.be.false

            // Don't allow to open contract if earn term is closed
            await expect(earn.openContract(0, 100, swapTarget, swapCallData)).to.be.revertedWith("Earn Term must be open")
        })
    })

    describe("Market Place", async () => {
        it("Should accept bid", async function () {
            let altaBalance = await altaContract.balanceOf(treasury)
            await altaContract.connect(signer).transfer(accountToFund, altaBalance)

            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale],
            })
            signer = await ethers.getSigner(usdcWhale)
            const usdcBalance = await usdcContract.balanceOf(usdcWhale)
            await usdcContract.connect(signer).transfer(accountToFund, usdcBalance)

            await earn.addTerm(time, usdcRate, altaRatio, usdcMax)
            expect(await earn.earnTerms(0)).to.be.not.null

            await earn.putSale(0)

            let earnContract0 = await earn.earnContracts(0)
            expect(earnContract0.status).to.be.equal(2)

            let amount = '20000000000000000000'
            await earn.makeBid(0, amount)

            let bids = await earn.getAllBids()
            expect(bids).to.be.not.null
            let bid0 = bids[0]
            expect(bid0.earnContractId).to.be.equal(0)
            expect(bid0.amount).to.be.equal(amount)

            altaBalance = await altaContract.balanceOf(earn.address)

            await earn.acceptBid(0)
            bids = await earn.getAllBids()
            bid0 = bids[0]
            expect(bid0).to.be.undefined

        })

        it("Should remove contract from market without bids", async function () {
            await earn.putSale(0)
            let earnContract0 = await earn.earnContracts(0)
            expect(earnContract0.status).to.be.equal(2)

            await earn.removeContractFromMarket(0)
            earnContract0 = await earn.earnContracts(0)
            expect(earnContract0.status).to.be.equal(0)
        })

        it("Should remove contract from market with bids", async function () {
            await earn.putSale(0)

            let earnContract0 = await earn.earnContracts(0)
            expect(earnContract0.status).to.be.equal(2)

            let amount = '20000000000000000000'
            await earn.makeBid(0, amount)

            let bids = await earn.getAllBids()
            expect(bids).to.be.not.null
            let bid0 = bids[0]
            expect(bid0.earnContractId).to.be.equal(0)
            expect(bid0.amount).to.be.equal(amount)

            await earn.removeContractFromMarket(0)
            earnContract0 = await earn.earnContracts(0)
            expect(earnContract0.status).to.be.equal(0)

            let contractBids = await earn.getBidsByContract(0)
            expect(contractBids[0]).to.be.undefined

            bids = await earn.getAllBids()
            bid0 = bids[0]
            expect(bid0).to.be.undefined
        })

        it("Should transfer contract ownership", async function () {

            const accountToFund = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"
            const newFeeAddress = '0x661Cd43A26B92995C5eE8A21Cc3D715FE830576e'
            const ethWhale = '0x73BCEb1Cd57C711feaC4224D062b0F6ff338501e'
            const [deployer] = await ethers.getSigners()

            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [treasury],
            })
            let signer = await ethers.getSigner(treasury)
            let altaBalance = await altaContract.balanceOf(treasury)
            await altaContract.connect(signer).transfer(accountToFund, altaBalance)

            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [treasury],
            })
            signer = await ethers.getSigner(treasury)

            const usdcBalance = await usdcContract.balanceOf(usdcWhale)
            await usdcContract.connect(signer).transfer(accountToFund, usdcBalance)

            let time: number = 365 // 1095 days = 3 years
            let usdcRate: number = 500 // 500 = 5%
            let altaRatio: number = 1000

            await earn.addTerm(time, usdcRate, altaRatio, usdcMax)
            expect(await earn.earnTerms(0)).to.be.not.null

            const earnContracts = await earn.getAllEarnContracts()
            expect(earnContracts).to.be.not.null

            let earnContract0 = earnContracts[0]
            expect(earnContract0).to.be.not.null
            expect(earnContract0.owner).to.be.equal(deployer.address)
            expect(earnContract0.usdcRate).to.be.equal(usdcRate)
            expect(earnContract0.status).to.be.equal(0)

            await earn.putSale(0)

            earnContract0 = await earn.earnContracts(0)
            expect(earnContract0.status).to.be.equal(2)

            let amount = '20000000000000000000'

            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [ethWhale],
            })
            signer = await ethers.getSigner(ethWhale)

            await signer.sendTransaction({
                to: treasury,
                value: ethers.utils.parseEther("1000"), // Sends exactly 1.0 ether
            })

            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [treasury],
            })
            signer = await ethers.getSigner(treasury)
            await altaContract.connect(signer).approve(earn.address, BigNumber.from(MAX_UINT))

            await altaContract.connect(deployer).transfer(treasury, amount)
            await earn.connect(signer).makeBid(0, amount)

            let bids = await earn.getAllBids()
            expect(bids).to.be.not.null
            let bid0 = bids[0]
            expect(bid0.earnContractId).to.be.equal(0)
            expect(bid0.amount).to.be.equal(amount)

            altaBalance = await altaContract.balanceOf(earn.address)

            await earn.setFeeAddress(newFeeAddress)

            let altaFeeBalanceBefore = await altaContract.balanceOf(newFeeAddress)

            await earn.setTransferFee(100) //10% transfer fee
            await earn.acceptBid(0)

            let altaFeeBalanceAfter = await altaContract.balanceOf(newFeeAddress)
            let expectedFee = '2000000000000000000'
            let altaFeeBalance = altaFeeBalanceAfter - altaFeeBalanceBefore
            expect(altaFeeBalance.toString()).to.be.equal(expectedFee)

            bids = await earn.getAllBids()
            bid0 = bids[0]
            expect(bid0).to.be.undefined
            await earn.closeContract(0)
            earnContract0 = await earn.earnContracts(0)
            expect(earnContract0.status).to.be.equal(1)
            expect(earnContract0.owner).to.be.equal(treasury)
        })

    })
})
