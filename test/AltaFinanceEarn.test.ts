import { expect } from 'chai'
import { ethers } from 'hardhat'
import { BigNumberish } from 'ethers'
import { BigNumber } from '@ethersproject/bignumber'

import { ALTA, USDC, LOAN_ADDRESS, USDT } from '../scripts/utils/address'
import { usdcABI } from '../scripts/abi/usdc'
import { altaABI } from '../scripts/abi/alta'
import { Earn, AltaFinanceEarn } from '../typechain-types/contracts/Earn'
import { Earn__factory, AltaFinanceEarn__factory } from '../typechain-types/factories/contracts/Earn'
import hre from "hardhat"

// TODO: Add testing for emitted events.

// List of variables that are reused throughout the tests
const treasury = '0x087183a411770a645A96cf2e31fA69Ab89e22F5E'
const usdcWhale = '0xfc7470c14baef608dc316f5702790eefee9cc258'
const MAX_UINT = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
const ethWhale = '0x73BCEb1Cd57C711feaC4224D062b0F6ff338501e'
const usdcWhale2 = "0xaf10cc6c50defff901b535691550d7af208939c5"
const accountToFund: string = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"
let earn: AltaFinanceEarn
let time: number = 1095 // 1095 days = 3 years
let tokens: string[] = [USDC]
let interestRate: number = 500 // 500 = 5%
let altaRatio: number = 30000 // 30000 = 300%
let altaContract: any
let usdcContract: any
let deployer: any
let signer: any

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

interface EarnTerm {
    time: BigNumber,
    usdcRate: number,
    altaHighAmount: BigNumber,
    altaMedAmount: BigNumber,
    altaLowAmount: BigNumber,
    otherTokens: boolean,
    whitelist: boolean,
    tokensAccepted: string[],
    usdcMax: BigNumber,
    usdcAccepted: BigNumber,
    open: boolean
}

interface Bid {
    bidder: string,
    to: string,
    earnContractId: BigNumber,
    amount: BigNumber,
    accepted: boolean
}

describe("Earn", async () => {
    before(async () => {
        let signers = await ethers.getSigners()
        deployer = signers[0]
        altaContract = new ethers.Contract(ALTA, JSON.parse(altaABI), deployer)
        usdcContract = new ethers.Contract(USDC, JSON.parse(usdcABI), deployer)

        await deployer.sendTransaction({
            to: treasury,
            value: ethers.utils.parseEther("1.0"), // Sends exactly 1.0 ether
        })

        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [treasury],
        })
        signer = await ethers.getSigner(treasury)
        await altaContract.connect(signer).transfer(usdcWhale, ethers.utils.parseEther("100000000.0"))
    })

    beforeEach(async function () {
        const Earn: AltaFinanceEarn__factory = (await ethers.getContractFactory("AltaFinanceEarn")) as AltaFinanceEarn__factory
        earn = await Earn.deploy(ALTA, LOAN_ADDRESS)
        await earn.updateAsset(USDC, true)

        await altaContract.connect(deployer).approve(earn.address, BigNumber.from(MAX_UINT))
        await altaContract.allowance(deployer.address, earn.address)
        await usdcContract.connect(deployer).approve(earn.address, BigNumber.from(MAX_UINT))
        await usdcContract.allowance(deployer.address, earn.address)

        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [treasury],
        })
        signer = await ethers.getSigner(treasury)
    })

    describe("Migration", async () => {
        it("should migrate contracts, terms, and bids", async () => {
            // const Earn = await ethers.getContractFactory("AltaFinanceEarn")
            // let earn = await Earn.deploy(ALTA, LOAN_ADDRESS)
            const EarnV1 = (await ethers.getContractFactory("Earn")) as Earn__factory
            const earnV1: Earn = EarnV1.attach("0x279493E1ED2F32FfDe533402969070539d3e926C")
            let oldContracts: EarnContract[] = []
            try {
                oldContracts = await earnV1.getAllEarnContracts()
            } catch (e) {
                oldContracts = []
            }

            let migratedContracts: {
                owner: string,
                termIndex: BigNumberish,
                startTime: BigNumberish,
                contractLength: BigNumberish,
                token: string,
                lentAmount: BigNumberish,
                baseTokenPaid: BigNumberish,
                altaPaid: BigNumberish,
                tier: number
                status: number
            }[] = []

            for (let i = 0; i < oldContracts.length; i++) {
                migratedContracts.push({
                    owner: oldContracts[i].owner, // owner
                    termIndex: BigNumber.from('0'), // termIndex
                    startTime: oldContracts[i].startTime, // startTime
                    contractLength: oldContracts[i].contractLength, // contractLength,
                    token: USDC, // tokenAddress
                    lentAmount: oldContracts[i].usdcPrincipal, // lentAmount
                    baseTokenPaid: oldContracts[i].usdcInterestPaid, //usdcInterestPaid
                    altaPaid: 0,
                    tier: 0, // tier
                    status: oldContracts[i].status // status
                })
            }

            let oldTerms: EarnTerm[] = []
            try {
                oldTerms = await earnV1.getAllEarnTerms()
            } catch (e) {
                oldTerms = []
            }

            let migratedTerms: {
                time: BigNumber,
                interestRate: number,
                altaRatio: BigNumber,
                open: boolean
            }[] = []

            for (let i = 0; i < oldTerms.length; i++) {
                migratedTerms.push({
                    time: oldTerms[i].time,
                    interestRate: oldTerms[i].usdcRate,
                    altaRatio: BigNumber.from("10000"),
                    open: oldTerms[i].open
                })
            }

            let oldBids: Bid[] = []
            try {
                oldBids = await earnV1.getAllBids()
            } catch {
                oldBids = []
            }

            await earn.migration(migratedContracts, migratedTerms, oldBids)

            let contract = await earn.getAllEarnContracts()
            expect(contract.length).to.equal(oldContracts.length)

            let terms = await earn.getAllEarnTerms()
            expect(terms.length).to.equal(oldTerms.length)

            let bids = await earn.getAllBids()
            expect(bids.length).to.equal(bids.length)
        })
    })

    describe("Setter Functions", async () => {
        it("Should set the Transfer Fee", async function () {
            let transferFee = await earn.transferFee()
            expect(transferFee).to.be.equal(3)
            await earn.setTransferFee(BigNumber.from(100))
            transferFee = await earn.transferFee()
            expect(transferFee).to.be.not.equal(3)
            expect(transferFee).to.be.equal(BigNumber.from(100))
        })

        it("Should set the Loan Address", async function () {
            let loanAddress = await earn.loanAddress()
            expect(loanAddress).to.be.equal(LOAN_ADDRESS)
            await earn.setLoanAddress(ALTA)
            loanAddress = await earn.loanAddress()
            expect(loanAddress).to.be.not.equal(LOAN_ADDRESS)
            expect(loanAddress).to.be.equal(ALTA)
        })

        it("Should add USDT as an accepted asset", async function () {
            expect(await earn.acceptedAssets(USDT)).to.be.false
            await earn.updateAsset(USDT, true)
            expect(await earn.acceptedAssets(USDT)).to.be.true
        })
        it("Should remove USDC as an accepted asset", async function () {
            expect(await earn.acceptedAssets(USDC)).to.be.true
            await earn.updateAsset(USDC, false)
            expect(await earn.acceptedAssets(USDC)).to.be.false
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
            expect(await earn.paused()).to.be.true

            let amount = "10000000000000000000000"
            await altaContract.connect(signer).transfer(accountToFund, amount)

            await earn.addTerm(time, interestRate, altaRatio)
            expect(await earn.earnTerms(0)).to.be.not.null

            await expect(earn.openContract(0, 100, USDC, 0)).to.be.revertedWith('Pausable: paused')
        })

        it("Should allow new contracts when unpaused", async function () {
            await earn.pause()
            expect(await earn.paused()).to.be.true

            await earn.unpause()
            expect(await earn.paused()).to.be.false
            await expect(earn.openContract(0, 100, USDC, 0)).to.not.be.revertedWith('Pausable: paused')
        })

        // it("Should not allow new contracts when paused", async function () {
        //     let amount = "10000000000000000000000"
        //     await altaContract.connect(signer).transfer(accountToFund, amount)

        //     await earn.addTerm(time, interestRate, altaRatio)
        //     expect(await earn.earnTerms(0)).to.be.not.null

        //     await earn.openContract(0, 100, USDC, 0)

        //     await earn.pause()
        //     expect(await earn.paused()).to.be.true
        // })
    })

    describe("Earn Terms", async () => {
        it("Should return the earnTerm when it's added", async function () {
            await earn.addTerm(time, interestRate, altaRatio)
            const earnTerm = await earn.earnTerms(0)

            expect(earnTerm).to.be.not.null
            expect(earnTerm.time).to.be.equal(time)
            expect(earnTerm.interestRate).to.be.equal(interestRate)
            expect(earnTerm.altaRatio).to.be.equal(altaRatio)
        })

        it("Should have multiple earnTerms in the array", async function () {
            await earn.addTerm(time, interestRate, altaRatio)
            expect(await earn.earnTerms(0)).to.be.not.null

            await earn.addTerm(time, interestRate, altaRatio)
            const earnTerms = await earn.getAllEarnTerms()
            expect(earnTerms.length).to.be.equal(2)
            expect(earnTerms[0]).to.be.not.null
            expect(earnTerms[1]).to.be.not.null
        })

        it("Should change status to closed when closeTerm is called", async function () {
            await earn.addTerm(time, interestRate, altaRatio)
            expect(await earn.earnTerms(0)).to.be.not.null

            await earn.addTerm(time, interestRate, altaRatio)
            let earnTerms = await earn.getAllEarnTerms()
            expect(earnTerms.length).to.be.equal(2)
            expect(earnTerms[0]).to.be.not.null
            expect(earnTerms[1]).to.be.not.null

            await earn.closeTerm(1)
            earnTerms = await earn.getAllEarnTerms()
            expect(earnTerms.length).to.be.equal(2)
            expect(earnTerms[0]).to.be.not.null
            expect(earnTerms[1]).to.be.not.null
            let earnTerm = await earn.earnTerms(1)
            expect(earnTerm.open).to.be.false
        })

        it("Should open a closed earnTerm", async function () {
            await earn.addTerm(time, interestRate, altaRatio)
            expect(await earn.earnTerms(0)).to.be.not.null

            await earn.closeTerm(0)
            let earnTerm = await earn.earnTerms(0)
            expect(earnTerm.open).to.be.false

            await earn.openTerm(0)
            earnTerm = await earn.earnTerms(0)
            expect(earnTerm.open).to.be.true
        })
    })

    describe("Earn Contracts", async () => {
        it("Should open contract with USDC in tier0", async function () {
            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale],
            })
            signer = await ethers.getSigner(usdcWhale)
            const usdcBalance = await usdcContract.balanceOf(usdcWhale)
            await usdcContract.connect(signer).approve(earn.address, BigNumber.from(MAX_UINT))

            await earn.addTerm(time, interestRate, altaRatio)
            expect(await earn.earnTerms(0)).to.be.not.null

            let amount = "10000000000" // $10,000 USDC
            const openContract = await earn.connect(signer).openContract(0, amount, USDC, 0)
            await openContract.wait()

            let earnContract = await earn.getAllEarnContracts()
            expect(earnContract.length).to.be.equal(1)
            expect(earnContract[0].tier).to.be.equal(0)
        })

        it("Should open contract with USDC in tier1", async function () {
            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale],
            })
            signer = await ethers.getSigner(usdcWhale)
            const usdcBalance = await usdcContract.balanceOf(usdcWhale)
            await usdcContract.connect(signer).approve(earn.address, BigNumber.from(MAX_UINT))

            await earn.addTerm(time, interestRate, altaRatio)
            expect(await earn.earnTerms(0)).to.be.not.null

            let altaTransfer = await earn.tier1Amount()

            expect(altaTransfer).to.be.equal("10000000000000000000000")

            await altaContract.connect(signer).approve(earn.address, altaTransfer)

            let amount = "10000000000" // $10,000 USDC
            const openContract = await earn.connect(signer).openContract(0, amount, USDC, BigNumber.from(altaTransfer))
            await openContract.wait()

            let earnContract = await earn.getAllEarnContracts()
            expect(earnContract.length).to.be.equal(1)
            expect(earnContract[0].tier).to.be.equal(1)
        })

        it("Should open contract with USDC in tier2", async function () {
            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale],
            })
            signer = await ethers.getSigner(usdcWhale)
            const usdcBalance = await usdcContract.balanceOf(usdcWhale)
            await usdcContract.connect(signer).approve(earn.address, BigNumber.from(MAX_UINT))

            await earn.addTerm(time, interestRate, altaRatio)
            expect(await earn.earnTerms(0)).to.be.not.null

            let altaTransfer = await earn.tier2Amount()

            expect(altaTransfer).to.be.equal("100000000000000000000000")

            await altaContract.connect(signer).approve(earn.address, altaTransfer)

            let amount = "10000000000" // $10,000 USDC
            const openContract = await earn.connect(signer).openContract(0, amount, USDC, BigNumber.from(altaTransfer))
            await openContract.wait()

            let earnContract = await earn.getAllEarnContracts()
            expect(earnContract.length).to.be.equal(1)
            expect(earnContract[0].tier).to.be.equal(2)
        })

        it("Should emit a ContractOpened event", async function () {
            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale],
            })
            signer = await ethers.getSigner(usdcWhale)
            const usdcBalance = await usdcContract.balanceOf(usdcWhale)
            await usdcContract.connect(signer).approve(earn.address, BigNumber.from(MAX_UINT))

            await earn.addTerm(time, interestRate, altaRatio)
            expect(await earn.earnTerms(0)).to.be.not.null

            let altaTransfer = await earn.tier2Amount()

            expect(altaTransfer).to.be.equal("100000000000000000000000")

            await altaContract.connect(signer).approve(earn.address, altaTransfer)

            let amount = "10000000000" // $10,000 USDC
            expect(await earn.connect(signer).openContract(0, amount, USDC, BigNumber.from(altaTransfer)))
                .to.emit(earn, 'ContractOpened')
                .withArgs(signer.address, 0)
        })

        it("Should revert openContract if term is closed", async function () {
            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale],
            })
            signer = await ethers.getSigner(usdcWhale)
            const usdcBalance = await usdcContract.balanceOf(usdcWhale)
            await usdcContract.connect(signer).approve(earn.address, BigNumber.from(MAX_UINT))

            await earn.addTerm(time, interestRate, altaRatio)
            expect(await earn.earnTerms(0)).to.be.not.null

            await earn.closeTerm(0)
            let earnTerm = await earn.earnTerms(0)
            expect(await earnTerm.open).to.be.false

            let amount = "10000000000" // $10,000 USDC
            // Don't allow to open contract if earn term is closed
            await expect(earn.openContract(0, amount, USDC, 0)).to.be.revertedWith("Earn Term must be open")

            let earnContract = await earn.getAllEarnContracts()
            expect(earnContract.length).to.be.equal(0)
        })

        it("Should transfer funds to the smart contract", async function () {
            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale],
            })
            signer = await ethers.getSigner(usdcWhale)
            const usdcBalance = await usdcContract.balanceOf(usdcWhale)
            await usdcContract.connect(signer).approve(earn.address, BigNumber.from(MAX_UINT))

            await earn.addTerm(time, interestRate, altaRatio)
            expect(await earn.earnTerms(0)).to.be.not.null

            let amount = "10000000000" // $10,000 USDC
            const openContract = await earn.connect(signer).openContract(0, amount, USDC, 0)
            await openContract.wait()

            let earnContract = await earn.getAllEarnContracts()
            expect(earnContract.length).to.be.equal(1)

            const usdcBalanceEarn = await usdcContract.balanceOf(earn.address)
            expect(usdcBalanceEarn).to.be.equal(amount)
        })

        it("Should only redeem interest before contract maturation", async function () {
            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale],
            })
            signer = await ethers.getSigner(usdcWhale)
            const usdcBalance = await usdcContract.balanceOf(usdcWhale)
            await usdcContract.connect(signer).approve(earn.address, BigNumber.from(MAX_UINT))

            await earn.addTerm(time, interestRate, altaRatio)
            expect(await earn.earnTerms(0)).to.be.not.null

            let amount = "10000000000" // $10,000 USDC
            const openContract = await earn.connect(signer).openContract(0, amount, USDC, 0)
            await openContract.wait()

            let earnContract = await earn.getAllEarnContracts()
            expect(earnContract.length).to.be.equal(1)

            let term = await earn.earnTerms(earnContract[0].termIndex)

            let blockTime = 0xD2F00 // 864000 seconds = 10 days

            // Test interest redemption
            await hre.network.provider.request({
                method: "evm_increaseTime",
                params: [blockTime] // 864000 seconds = 10 days
            })

            await hre.network.provider.request({
                method: "hardhat_mine",
                params: ["0x1"] // 1 block
            })

            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale2],
            })

            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [treasury],
            })
            let tSigner = await ethers.getSigner(treasury)
            await altaContract.connect(tSigner).transfer(earn.address, ethers.utils.parseEther("10000.0"))

            let whale = await ethers.getSigner(usdcWhale2)
            await usdcContract.connect(whale).transfer(earn.address, "1000000000000")

            let usdcBalanceBefore = await usdcContract.balanceOf(signer.address)
            let altaBalanceBefore = await altaContract.balanceOf(signer.address)
            expect(await earn.connect(signer).redeem(0)).to.not.Throw
            let usdcBalanceAfter = await usdcContract.balanceOf(signer.address)
            let altaBalanceAfter = await altaContract.balanceOf(signer.address)
            expect(Number(usdcBalanceAfter)).to.be.greaterThan(Number(usdcBalanceBefore))
            // expect(Number(altaBalanceAfter)).to.be.greaterThan(Number(altaBalanceBefore))

            let usdcRedeemed = usdcBalanceAfter.sub(usdcBalanceBefore)
            expect(Number(usdcRedeemed)).to.be.lessThan(Number(amount))

            let altaRedeemed = altaBalanceAfter.sub(altaBalanceBefore)
            let contractLength = BigNumber.from(term.time).mul(24 * 60 * 60)
            let expectedAlta
            try {
                expectedAlta = BigNumber.from(amount).mul(term.altaRatio).div(10000).mul(blockTime / Number(contractLength))
            } catch {
                expectedAlta = 0
            }

            expect(Number(altaRedeemed)).to.be.equal(expectedAlta)

        })

        it("Should emit a Redemption event", async function () {
            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale],
            })
            signer = await ethers.getSigner(usdcWhale)
            await usdcContract.connect(signer).approve(earn.address, BigNumber.from(MAX_UINT))

            await earn.addTerm(time, interestRate, altaRatio)

            let amount = "10000000000" // $10,000 USDC
            const openContract = await earn.connect(signer).openContract(0, amount, USDC, 0)
            await openContract.wait()

            let earnContract = await earn.getAllEarnContracts()

            let term = await earn.earnTerms(earnContract[0].termIndex)

            let blockTime = 0xD2F00 // 864000 seconds = 10 days

            // Test interest redemption
            await hre.network.provider.request({
                method: "evm_increaseTime",
                params: [blockTime] // 864000 seconds = 10 days
            })

            await hre.network.provider.request({
                method: "hardhat_mine",
                params: ["0x1"] // 1 block
            })

            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale2],
            })

            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [treasury],
            })
            let tSigner = await ethers.getSigner(treasury)
            await altaContract.connect(tSigner).transfer(earn.address, ethers.utils.parseEther("10000.0"))

            let whale = await ethers.getSigner(usdcWhale2)
            await usdcContract.connect(whale).transfer(earn.address, "1000000000000")

            expect(await earn.connect(signer).redeem(0))
                .to.emit(earn, "Redemption")
                .withArgs(signer.address, 0, USDC, amount, 0)

        })

        it("Should redeem principal and close contract after maturation", async function () {
            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale],
            })
            signer = await ethers.getSigner(usdcWhale)
            const usdcBalance = await usdcContract.balanceOf(usdcWhale)
            await usdcContract.connect(signer).approve(earn.address, BigNumber.from(MAX_UINT))

            await earn.addTerm(time, interestRate, altaRatio)
            expect(await earn.earnTerms(0)).to.be.not.null

            let amount = "10000000000" // $10,000 USDC
            const openContract = await earn.connect(signer).openContract(0, amount, USDC, 0)
            await openContract.wait()

            let earnContract = await earn.getAllEarnContracts()
            expect(earnContract.length).to.be.equal(1)

            let term = await earn.earnTerms(earnContract[0].termIndex)

            let blockTime = 0x5A39A80 // 94608000 seconds = 1095 days

            await hre.network.provider.request({
                method: "evm_increaseTime",
                params: [blockTime] // 94608000 seconds = 1095 days
            })

            await hre.network.provider.request({
                method: "hardhat_mine",
                params: ["0x1"] // 1 block
            })

            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale2],
            })
            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [treasury],
            })
            let tSigner = await ethers.getSigner(treasury)
            await altaContract.connect(tSigner).transfer(earn.address, ethers.utils.parseEther("10000.0"))

            let whale = await ethers.getSigner(usdcWhale2)
            await usdcContract.connect(whale).transfer(earn.address, "1000000000000")

            // await altaContract.connect(signer).transfer(earn.address, BigNumber.from(amount).mul(1000))
            let usdcBalanceBefore = await usdcContract.balanceOf(signer.address)
            let altaBalanceBefore = await altaContract.balanceOf(signer.address)
            expect(await earn.connect(signer).redeem(0)).to.not.Throw
            let usdcBalanceAfter = await usdcContract.balanceOf(signer.address)
            let altaBalanceAfter = await altaContract.balanceOf(signer.address)
            expect(Number(usdcBalanceAfter)).to.be.greaterThan(Number(usdcBalanceBefore))
            expect(Number(altaBalanceAfter)).to.be.greaterThan(Number(altaBalanceBefore))

            let usdcRedeemed = usdcBalanceAfter.sub(usdcBalanceBefore)
            expect(Number(usdcRedeemed)).to.be.greaterThan(Number(amount))

            let altaRedeemed = altaBalanceAfter.sub(altaBalanceBefore)
            let contractLength = BigNumber.from(term.time).mul(24 * 60 * 60)
            let expectedAlta
            try {
                expectedAlta = BigNumber.from(amount).mul(term.altaRatio).div(10000).mul(blockTime / Number(contractLength))
            } catch {
                expectedAlta = 0
            }

            expect(Number(altaRedeemed)).to.be.equal(expectedAlta)
        })

        it("Should emit a ContractClosed event", async function () {
            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale],
            })
            signer = await ethers.getSigner(usdcWhale)
            const usdcBalance = await usdcContract.balanceOf(usdcWhale)
            await usdcContract.connect(signer).approve(earn.address, BigNumber.from(MAX_UINT))

            await earn.addTerm(time, interestRate, altaRatio)
            expect(await earn.earnTerms(0)).to.be.not.null

            let amount = "10000000000" // $10,000 USDC
            const openContract = await earn.connect(signer).openContract(0, amount, USDC, 0)
            await openContract.wait()

            let earnContract = await earn.getAllEarnContracts()
            expect(earnContract.length).to.be.equal(1)

            let term = await earn.earnTerms(earnContract[0].termIndex)

            let blockTime = 0x5A39A80 // 94608000 seconds = 1095 days

            await hre.network.provider.request({
                method: "evm_increaseTime",
                params: [blockTime] // 94608000 seconds = 1095 days
            })

            await hre.network.provider.request({
                method: "hardhat_mine",
                params: ["0x1"] // 1 block
            })

            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale2],
            })
            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [treasury],
            })
            let tSigner = await ethers.getSigner(treasury)
            await altaContract.connect(tSigner).transfer(earn.address, ethers.utils.parseEther("10000.0"))

            let whale = await ethers.getSigner(usdcWhale2)
            await usdcContract.connect(whale).transfer(earn.address, "1000000000000")

            expect(await earn.connect(signer).redeem(0))
                .to.emit(earn, 'ContractClosed')
                .withArgs(signer.address, 0)
        })

        it("Should redeem all contracts owned by signer", async function () {

        })
    })

    describe("Market Place", async () => {
        it("Should make & accept bid", async function () {
            let altaBalance = await altaContract.balanceOf(treasury)
            await altaContract.connect(signer).transfer(accountToFund, altaBalance)

            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale],
            })
            signer = await ethers.getSigner(usdcWhale)
            const usdcBalance = await usdcContract.balanceOf(usdcWhale)
            await usdcContract.connect(signer).approve(earn.address, BigNumber.from(MAX_UINT))

            await earn.addTerm(time, interestRate, altaRatio)
            expect(await earn.earnTerms(0)).to.be.not.null

            let amount = "10000000000" // $10,000 USDC
            const openContract = await earn.connect(signer).openContract(0, amount, USDC, 0)
            await openContract.wait()

            let earnContract = await earn.getAllEarnContracts()
            expect(earnContract.length).to.be.equal(1)

            await earn.connect(signer).putSale(0)

            let earnContract0 = await earn.earnContracts(0)
            expect(earnContract0.status).to.be.equal(2)

            amount = '20000000000000000000'
            await earn.connect(deployer).makeBid(0, amount)

            let bids = await earn.getAllBids()
            expect(bids).to.be.not.null
            let bid0 = bids[0]
            expect(bid0.earnContractId).to.be.equal(0)
            expect(bid0.amount).to.be.equal(amount)

            altaBalance = await altaContract.balanceOf(earn.address)

            await earn.connect(signer).acceptBid(0)
            bids = await earn.getAllBids()
            bid0 = bids[0]
            expect(bid0).to.be.undefined

            earnContract0 = await earn.earnContracts(0)
            // successfully transfer ownership after acceptBid
            expect(earnContract0.owner).to.be.equal(deployer.address)
        })

        it("Should emit a BidMade and EarnContractOwnershipTransferred event", async function () {
            let altaBalance = await altaContract.balanceOf(treasury)
            await altaContract.connect(signer).transfer(accountToFund, altaBalance)

            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale],
            })
            signer = await ethers.getSigner(usdcWhale)
            await usdcContract.connect(signer).approve(earn.address, BigNumber.from(MAX_UINT))

            await earn.addTerm(time, interestRate, altaRatio)
            expect(await earn.earnTerms(0)).to.be.not.null

            let amount = "10000000000" // $10,000 USDC
            const openContract = await earn.connect(signer).openContract(0, amount, USDC, 0)
            await openContract.wait()

            await earn.connect(signer).putSale(0)

            amount = '20000000000000000000'
            expect(await earn.connect(deployer).makeBid(0, amount))
                .to.emit(earn, "BidMade")
                .withArgs(deployer.address, 0)

            altaBalance = await altaContract.balanceOf(earn.address)

            expect(await earn.connect(signer).acceptBid(0))
                .to.emit(earn, 'EarnContractOwnershipTransferred')
                .withArgs(signer.address, deployer.address, 0)

        })

        it("Should remove contract from market without bids", async function () {
            let altaBalance = await altaContract.balanceOf(treasury)
            await altaContract.connect(signer).transfer(accountToFund, altaBalance)

            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale],
            })
            signer = await ethers.getSigner(usdcWhale)
            const usdcBalance = await usdcContract.balanceOf(usdcWhale)
            await usdcContract.connect(signer).approve(earn.address, BigNumber.from(MAX_UINT))

            await earn.addTerm(time, interestRate, altaRatio)
            expect(await earn.earnTerms(0)).to.be.not.null

            let amount = "10000000000" // $10,000 USDC
            const openContract = await earn.connect(signer).openContract(0, amount, USDC, 0)
            await openContract.wait()

            let earnContract = await earn.getAllEarnContracts()
            expect(earnContract.length).to.be.equal(1)

            await earn.connect(signer).putSale(0)
            let earnContract0 = await earn.earnContracts(0)
            expect(earnContract0.status).to.be.equal(2)

            await earn.connect(signer).removeContractFromMarket(0)
            earnContract0 = await earn.earnContracts(0)
            expect(earnContract0.status).to.be.equal(0)
        })

        it("Should remove contract from market with bids", async function () {
            let altaBalance = await altaContract.balanceOf(treasury)
            await altaContract.connect(signer).transfer(accountToFund, altaBalance)

            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale],
            })
            signer = await ethers.getSigner(usdcWhale)
            const usdcBalance = await usdcContract.balanceOf(usdcWhale)
            await usdcContract.connect(signer).approve(earn.address, BigNumber.from(MAX_UINT))

            await earn.addTerm(time, interestRate, altaRatio)
            expect(await earn.earnTerms(0)).to.be.not.null

            let amount = "10000000000" // $10,000 USDC
            const openContract = await earn.connect(signer).openContract(0, amount, USDC, 0)
            await openContract.wait()

            let earnContract = await earn.getAllEarnContracts()
            expect(earnContract.length).to.be.equal(1)

            expect(await earn.connect(signer).putSale(0))
                .to.emit(earn, "ContractForSale")
                .withArgs(0)

            let earnContract0 = await earn.earnContracts(0)
            expect(earnContract0.status).to.be.equal(2)

            amount = '20000000000000000000'
            await earn.makeBid(0, amount)

            let bids = await earn.getAllBids()
            expect(bids).to.be.not.null
            let bid0 = bids[0]
            expect(bid0.earnContractId).to.be.equal(0)
            expect(bid0.amount).to.be.equal(amount)

            await earn.connect(signer).removeContractFromMarket(0)
            earnContract0 = await earn.earnContracts(0)
            expect(earnContract0.status).to.be.equal(0)

            bids = await earn.getAllBids()
            bid0 = bids[0]
            expect(bid0).to.be.undefined
        })
    })

    describe("EarnBase Functions", async () => {
        it("Should withdraw token", async function () {
            await hre.network.provider.request({
                method: "hardhat_impersonateAccount",
                params: [usdcWhale],
            })
            signer = await ethers.getSigner(usdcWhale)
            let usdcAmount = BigNumber.from("1000000000")
            await usdcContract.connect(signer).transfer(earn.address, usdcAmount)

            let balance = await usdcContract.balanceOf(earn.address)
            expect(balance).to.be.equal(Number(usdcAmount))

            await earn.withdrawToken(USDC, accountToFund, usdcAmount)
            let accountUsdcBalance = await usdcContract.balanceOf(accountToFund)
            expect(accountUsdcBalance).to.be.equal(Number(usdcAmount))
        })

        it("Should transfer eth from contract", async function () {
            await signer.sendTransaction({
                to: earn.address,
                value: ethers.utils.parseEther("1"),
                gasLimit: 25000,
            })
            let randomAccount = "0x51D9a5A57D4D4140e605B6f878a349c3eb4527f4"

            let balance = await ethers.provider.getBalance(earn.address)
            expect(balance).to.be.equal(ethers.utils.parseEther("1"))

            await earn.transfer(randomAccount, ethers.utils.parseEther("1"))
            balance = await ethers.provider.getBalance(randomAccount)
            expect(balance).to.be.equal(ethers.utils.parseEther("1"))
        })
    })
})