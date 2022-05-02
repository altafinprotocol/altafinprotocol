//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./EarnBase.sol";

/// @title Alta Finance Earn
/// @author Alta Finance Team
/// @notice This contract is a lending protocol where consumers lend ALTA and receive stable yields secured by real assets.
contract AltaFinanceEarn is EarnBase {
    using SafeERC20 for IERC20;

    /// ALTA token
    IERC20 public ALTA;

    /// Address of wallet to receive funds
    address public loanAddress;

    /// Percent of bid amount transferred to Alta Finance as a service fee (100 = 10%)
    uint256 public transferFee; // 100 = 10%

    uint256 public tier1Amount; //amount of alta to stake to reach tier 1
    uint256 public tier2Amount; // amount of alta to stake to reach tier 2

    uint256 public immutable tier1Multiplier = 1150; // 1150 = 1.15x
    uint256 public immutable tier2Multiplier = 1250; // 1250 = 1.25x

    /// Boolean variable to guard against multiple migration attempts
    bool migrated = false;

    /// @param owner Address of the contract owner
    /// @param earnContractId index of earn contracat in earnContracts
    event ContractOpened(address indexed owner, uint256 earnContractId);

    /// @param owner Address of the contract owner
    /// @param earnContractId index of earn contract in earnContracts
    event ContractClosed(address indexed owner, uint256 earnContractId);

    /// @param previousOwner Address of the previous contract owner
    /// @param newOwner Address of the new contract owner
    /// @param earnContractId Index of earn contract in earnContracts
    event EarnContractOwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner,
        uint256 earnContractId
    );

    /// @param owner Address of the contract owner
    /// @param token Address of the token redeemed
    /// @param tokenAmount Amount of token redeemed
    /// @param altaAmount amount of ALTA redeemed
    event Redemption(
        address indexed owner,
        uint256 earnContractId,
        address token,
        uint256 tokenAmount,
        uint256 altaAmount
    );

    /// @param bidder Address of the bidder
    /// @param bidId Index of bid in bids
    event BidMade(address indexed bidder, uint256 bidId);

    /// @param earnContractId Index of earn contract in earnContracts
    event ContractForSale(uint256 earnContractId);

    /// @param earnContractId Index of earn contract in earnContracts
    event ContractOffMarket(uint256 earnContractId);

    constructor(IERC20 _ALTA, address _loanAddress) {
        ALTA = _ALTA;
        loanAddress = _loanAddress;
        transferFee = 3; // 3 = .3%
        tier1Amount = 10000 * (10**18); // 10,000 ALTA
        tier2Amount = 100000 * (10**18); // 100,000 ALTA
    }

    enum ContractStatus {
        OPEN,
        CLOSED,
        FORSALE
    }

    enum Tier {
        TIER0,
        TIER1,
        TIER2
    }

    struct EarnTerm {
        uint256 time; // Time Locked (in Days);
        uint16 interestRate; // Base APR (simple interest) (1000 = 10%)
        uint64 altaRatio; // ALTA ratio
        bool open; // True if open, False if closed
    }

    struct EarnContract {
        address owner; // Contract Owner Address
        uint256 termIndex; // Index of Earn Term
        uint256 startTime; // Unix Epoch time started
        uint256 contractLength; // length of contract in seconds
        address token; // Token Address
        uint256 lentAmount; // Amount of token lent
        uint256 baseTokenPaid; // Base Interest Paid
        uint256 altaPaid; // ALTA Interest Paid
        Tier tier; // TIER0, TIER1, TIER2
        ContractStatus status; // Open, Closed, or ForSale
    }

    struct Bid {
        address bidder; // Bid Owner Address
        address to; // Address of Contract Owner
        uint256 earnContractId; // Earn Contract Id
        uint256 amount; // ALTA Amount
        bool accepted; // Accepted - false if pending
    }

    EarnTerm[] public earnTerms;
    EarnContract[] public earnContracts;
    Bid[] public bids;
    mapping(address => bool) public acceptedAssets;

    /// @param _time Length of the contract in days
    /// @param _interestRate Base interest rate (1000 = 10%)
    /// @param _altaRatio Interest rate for ALTA (1000 = 10%)
    /// @dev Add an earn term with 8 parameters
    function addTerm(
        uint256 _time,
        uint16 _interestRate,
        uint64 _altaRatio
    ) public onlyOwner {
        earnTerms.push(EarnTerm(_time, _interestRate, _altaRatio, true));
    }

    /// @param _earnTermsId index of the earn term in earnTerms
    function closeTerm(uint256 _earnTermsId) public onlyOwner {
        require(_earnTermsId < earnTerms.length);
        earnTerms[_earnTermsId].open = false;
    }

    /// @param _earnTermsId index of the earn term in earnTerms
    function openTerm(uint256 _earnTermsId) public onlyOwner {
        require(_earnTermsId < earnTerms.length);
        earnTerms[_earnTermsId].open = true;
    }

    /// @return An array of type EarnTerm
    function getAllEarnTerms() public view returns (EarnTerm[] memory) {
        return earnTerms;
    }

    /// @return An array of type Bid
    function getAllBids() public view returns (Bid[] memory) {
        return bids;
    }

    /// Sends erc20 token to AltaFin Treasury Address and creates a contract with EarnContract[_id] terms for user.
    /// @param _earnTermsId index of the earn term in earnTerms
    /// @param _amount Amount of token to be lent
    /// @param _token Token Address
    /// @param _altaStake Amount of Alta to stake in contract
    function openContract(
        uint256 _earnTermsId,
        uint256 _amount,
        IERC20 _token,
        uint256 _altaStake
    ) public whenNotPaused {
        require(_amount > 0, "Token amount must be greater than zero");

        EarnTerm memory earnTerm = earnTerms[_earnTermsId];
        require(earnTerm.open, "Earn Term must be open");

        require(acceptedAssets[address(_token)], "Token not accepted");

        // User needs to first approve the token to be spent
        require(
            _token.balanceOf(address(msg.sender)) >= _amount,
            "Insufficient Tokens"
        );

        _token.safeTransferFrom(msg.sender, address(this), _amount);

        if (_altaStake > 0) {
            ALTA.safeTransferFrom(msg.sender, address(this), _altaStake);
        }

        Tier tier = getTier(_altaStake);

        // Convert time of earnTerm from days to seconds
        uint256 earnSeconds = earnTerm.time * 1 days;

        _createContract(
            _earnTermsId,
            earnSeconds,
            address(_token),
            _amount,
            tier
        );
    }

    /// @param _earnTermsId index of the earn term in earnTerms
    /// @param _earnSeconds Length of the contract in seconds
    /// @param _lentAmount Amount of token lent
    function _createContract(
        uint256 _earnTermsId,
        uint256 _earnSeconds,
        address _token,
        uint256 _lentAmount,
        Tier tier
    ) internal {
        EarnContract memory earnContract = EarnContract(
            msg.sender, // owner
            _earnTermsId, // termIndex
            block.timestamp, // startTime
            _earnSeconds, //contractLength,
            _token, // token
            _lentAmount, // lentAmount
            0, // baseTokenPaid
            0, // altaPaid
            tier, // tier
            ContractStatus.OPEN
        );

        earnContracts.push(earnContract);
        uint256 id = earnContracts.length - 1;
        emit ContractOpened(msg.sender, id);
    }

    /// @notice redeem the currrent base token + ALTA interest available for the contract
    /// @param _earnContractId index of earn contract in earnContracts
    function redeem(uint256 _earnContractId) public {
        EarnContract memory earnContract = earnContracts[_earnContractId];
        require(earnContract.owner == msg.sender);
        (uint256 baseTokenAmount, uint256 altaAmount) = redeemableValue(
            _earnContractId
        );
        earnContract.baseTokenPaid += baseTokenAmount;
        earnContract.altaPaid += altaAmount;

        if (
            block.timestamp >=
            earnContract.startTime + earnContract.contractLength
        ) {
            _closeContract(_earnContractId);
        }
        emit Redemption(
            msg.sender,
            _earnContractId,
            earnContract.token,
            baseTokenAmount,
            altaAmount
        );
        IERC20 Token = IERC20(earnContract.token);
        Token.safeTransfer(msg.sender, baseTokenAmount);
        ALTA.safeTransfer(msg.sender, altaAmount);
    }

    function redeemAll() public {
        uint256 length = earnContracts.length; // gas optimization
        EarnContract[] memory _contracts = earnContracts; // gas optimization
        for (uint256 i = 0; i < length; i++) {
            if (_contracts[i].owner == msg.sender) {
                redeem(i);
            }
        }
    }

    /// @param _earnContractId index of earn contract in earnContracts
    function _closeContract(uint256 _earnContractId) internal {
        require(
            earnContracts[_earnContractId].status != ContractStatus.CLOSED,
            "Contract is already closed"
        );
        require(
            _earnContractId < earnContracts.length,
            "Contract does not exist"
        );

        address owner = earnContracts[_earnContractId].owner;
        emit ContractClosed(owner, _earnContractId);

        _removeAllContractBids(_earnContractId);
        earnContracts[_earnContractId].status = ContractStatus.CLOSED;
    }

    /// @dev calculate the currrent base token + ALTA available for the contract
    /// @param _earnContractId index of earn contract in earnContracts
    /// @return baseTokenAmount Base token amount
    /// @return altaAmount ALTA amount
    function redeemableValue(uint256 _earnContractId)
        public
        view
        returns (uint256 baseTokenAmount, uint256 altaAmount)
    {
        EarnContract memory earnContract = earnContracts[_earnContractId];
        EarnTerm memory earnTerm = earnTerms[earnContract.termIndex];

        uint256 timeOpen = block.timestamp -
            earnContracts[_earnContractId].startTime;

        uint256 interestRate = _getInterestRate(
            earnTerm.interestRate,
            earnContract.tier
        );

        if (timeOpen <= earnContract.contractLength) {
            // Just interest
            baseTokenAmount =
                (earnContract.lentAmount * interestRate * timeOpen) /
                365 days /
                10000;

            // Calculate the total amount of alta rewards accrued
            altaAmount = (((earnContract.lentAmount * earnTerm.altaRatio) /
                10000) * (timeOpen / earnContract.contractLength));
        } else {
            // Calculate the total amount of base token to be paid out (principal + interest)
            uint256 baseRegInterest = ((earnContract.lentAmount *
                interestRate *
                earnContract.contractLength) /
                365 days /
                10000);

            baseTokenAmount = baseRegInterest + earnContract.lentAmount;

            // Calculate the total amount of alta rewards accrued
            altaAmount = ((earnContract.lentAmount * earnTerm.altaRatio) /
                10000);
        }

        baseTokenAmount = baseTokenAmount - earnContract.baseTokenPaid;
        altaAmount = altaAmount - earnContract.altaPaid;
        return (baseTokenAmount, altaAmount);
    }

    /// @dev calculate the currrent base token + ALTA available for the contract
    /// @param _earnContractId index of earn contract in earnContracts
    /// @return baseTokenAmount Base token  amount
    /// @return altaAmount ALTA amount
    function redeemableValue(uint256 _earnContractId, uint256 _time)
        public
        view
        returns (uint256 baseTokenAmount, uint256 altaAmount)
    {
        require(_time >= earnContracts[_earnContractId].startTime);
        EarnContract memory earnContract = earnContracts[_earnContractId];
        EarnTerm memory earnTerm = earnTerms[earnContract.termIndex];

        uint256 timeOpen = _time - earnContracts[_earnContractId].startTime;

        uint256 interestRate = _getInterestRate(
            earnTerm.interestRate,
            earnContract.tier
        );

        if (timeOpen <= earnContract.contractLength) {
            // Just interest
            baseTokenAmount =
                (earnContract.lentAmount * interestRate * timeOpen) /
                365 days /
                10000;

            // Calculate the total amount of alta rewards accrued
            altaAmount = (((earnContract.lentAmount * earnTerm.altaRatio) /
                10000) * (timeOpen / earnContract.contractLength));
        } else {
            // Calculate the total amount of base token to be paid out (principal + interest)
            uint256 baseRegInterest = ((earnContract.lentAmount *
                interestRate *
                earnContract.contractLength) /
                365 days /
                10000);

            baseTokenAmount = baseRegInterest + earnContract.lentAmount;

            // Calculate the total amount of alta rewards accrued
            altaAmount = ((earnContract.lentAmount * earnTerm.altaRatio) /
                10000);
        }

        baseTokenAmount = baseTokenAmount - earnContract.baseTokenPaid;
        altaAmount = altaAmount - earnContract.altaPaid;
        return (baseTokenAmount, altaAmount);
    }

    function _getInterestRate(uint256 _interestRate, Tier _tier)
        internal
        pure
        returns (uint256)
    {
        if (_tier == Tier.TIER0) {
            return _interestRate;
        } else if (_tier == Tier.TIER1) {
            return ((_interestRate * tier1Multiplier) / 1000);
        } else {
            return ((_interestRate * tier2Multiplier) / 1000);
        }
    }

    /// @return array of all earn contracts
    function getAllEarnContracts() public view returns (EarnContract[] memory) {
        return earnContracts;
    }

    /// @notice Lists the associated earn contract for sale on the market
    /// @param _earnContractId index of earn contract in earnContracts
    function putSale(uint256 _earnContractId) external whenNotPaused {
        require(
            msg.sender == earnContracts[_earnContractId].owner,
            "Msg.sender is not the owner"
        );
        earnContracts[_earnContractId].status = ContractStatus.FORSALE;
        emit ContractForSale(_earnContractId);
    }

    /// @notice Submits a bid for an earn contract on sale in the market
    /// @dev User must sign an approval transaction for first. ALTA.approve(address(this), _amount);
    /// @param _earnContractId index of earn contract in earnContracts
    /// @param _amount Amount of ALTA offered for bid
    function makeBid(uint256 _earnContractId, uint256 _amount)
        external
        whenNotPaused
    {
        EarnContract memory earnContract = earnContracts[_earnContractId];
        require(
            earnContract.status == ContractStatus.FORSALE,
            "Contract not for sale"
        );
        require(msg.sender != earnContract.owner, "Cannot bid on own contract");

        Bid memory bid = Bid(
            msg.sender, // bidder
            earnContract.owner, // to
            _earnContractId, // earnContractId
            _amount, // amount
            false // accepted
        );

        bids.push(bid);
        uint256 bidId = bids.length - 1;

        ALTA.safeTransferFrom(msg.sender, address(this), _amount);
        emit BidMade(msg.sender, bidId);
    }

    /// @notice Transfers the bid amount to the owner of the earn contract and transfers ownership of the contract to the bidder
    /// @param _bidId index of bid in Bids
    function acceptBid(uint256 _bidId) external whenNotPaused {
        Bid memory bid = bids[_bidId];
        uint256 earnContractId = bid.earnContractId;

        require(
            msg.sender == earnContracts[earnContractId].owner,
            "Msg.sender is not the owner"
        );

        uint256 fee = (bid.amount * transferFee) / 1000;

        if (fee > 0) {
            ALTA.safeTransfer(loanAddress, fee);
            bid.amount = bid.amount - fee;
        }
        ALTA.safeTransfer(bid.to, bid.amount);

        bids[_bidId].accepted = true;

        emit EarnContractOwnershipTransferred(
            bid.to,
            bid.bidder,
            earnContractId
        );
        earnContracts[earnContractId].owner = bid.bidder;

        _removeContractFromMarket(earnContractId);
    }

    /// @notice Remove Contract From Market
    /// @param _earnContractId index of earn contract in earnContracts
    function removeContractFromMarket(uint256 _earnContractId) external {
        require(
            msg.sender == earnContracts[_earnContractId].owner,
            "Msg.sender is not the owner"
        );
        _removeContractFromMarket(_earnContractId);
    }

    /// @notice Removes all contracts bids and sets the status flag back to open
    /// @param _earnContractId index of earn contract in earnContracts
    function _removeContractFromMarket(uint256 _earnContractId) internal {
        earnContracts[_earnContractId].status = ContractStatus.OPEN;
        _removeAllContractBids(_earnContractId);
        emit ContractOffMarket(_earnContractId);
    }

    /// @notice Sends all bid funds for an earn contract back to the bidder and removes them arrays and mappings
    /// @param _earnContractId index of earn contract in earnContracts
    function _removeAllContractBids(uint256 _earnContractId) internal {
        uint256 length = bids.length; // gas optimization
        Bid[] memory _bids = bids; // gas optimization
        if (length > 0) {
            for (uint256 i = length; i > 0; i--) {
                uint256 bidId = i - 1;
                if (_bids[bidId].earnContractId == _earnContractId) {
                    if (_bids[bidId].accepted != true) {
                        ALTA.safeTransfer(
                            _bids[bidId].bidder,
                            _bids[bidId].amount
                        );
                    }
                    _removeBid(bidId);
                }
            }
        }
    }

    /// @notice Sends bid funds back to bidder and removes the bid from the array
    /// @param _bidId index of bid in Bids
    function removeBid(uint256 _bidId) external {
        Bid memory bid = bids[_bidId];
        require(msg.sender == bid.bidder, "Msg.sender is not the bidder");
        ALTA.safeTransfer(bid.bidder, bid.amount);

        _removeBid(_bidId);
    }

    /// @param _bidId index of bid in Bids
    function _removeBid(uint256 _bidId) internal {
        require(_bidId < bids.length, "Bid ID longer than array length");

        if (bids.length > 1) {
            bids[_bidId] = bids[bids.length - 1];
        }
        bids.pop();
    }

    /// Set the transfer fee rate for contracts sold on the market place
    /// @param _transferFee Percent of accepted earn contract bid to be sent to AltaFin wallet
    function setTransferFee(uint256 _transferFee) external onlyOwner {
        transferFee = _transferFee;
    }

    /// @notice Set ALTA ERC20 token address
    /// @param _ALTA Address of ALTA Token contract
    function setAltaAddress(address _ALTA) external onlyOwner {
        ALTA = IERC20(_ALTA);
    }

    /// @notice Set the loanAddress
    /// @param _loanAddress Wallet address to recieve loan funds
    function setLoanAddress(address _loanAddress) external onlyOwner {
        require(_loanAddress != address(0));
        loanAddress = _loanAddress;
    }

    function getTier(uint256 _altaStaked) internal view returns (Tier) {
        if (_altaStaked < tier1Amount) {
            return Tier.TIER0;
        } else if (_altaStaked < tier2Amount) {
            return Tier.TIER1;
        } else {
            return Tier.TIER2;
        }
    }

    function setStakeAmounts(uint256 _tier1Amount, uint256 _tier2Amount)
        external
        onlyOwner
    {
        tier1Amount = _tier1Amount;
        tier2Amount = _tier2Amount;
    }

    function updateAsset(address _asset, bool _accepted) external onlyOwner {
        acceptedAssets[_asset] = _accepted;
    }

    /// @param _contracts Array of contracts to be migrated
    /// @param _terms Array of terms to be migrated
    /// @notice This function can only be called once.
    function migration(
        EarnContract[] memory _contracts,
        EarnTerm[] memory _terms,
        Bid[] memory _bids
    ) external onlyOwner {
        require(migrated == false, "Contract has already been migrated");
        for (uint256 i = 0; i < _contracts.length; i++) {
            _migrateContract(_contracts[i]);
        }
        for (uint256 i = 0; i < _terms.length; i++) {
            _migrateTerm(_terms[i]);
        }
        for (uint256 i = 0; i < _bids.length; i++) {
            _migrateBid(_bids[i]);
        }
        migrated = true;
    }

    /// @param mContract Contract to be migrated
    /// @notice This function will only be called once.
    function _migrateContract(EarnContract memory mContract) internal {
        earnContracts.push(mContract); // add the contract to the array
        uint256 id = earnContracts.length - 1; // get the id of the earnContract
        emit ContractOpened(mContract.owner, id); // emit the event
    }

    /// @param mTerm Term to be migrated
    /// @notice This function will only be called once.
    function _migrateTerm(EarnTerm memory mTerm) internal {
        earnTerms.push(mTerm); // add the term to the array
    }

    /// @param mBid Bid to be migrated
    /// @notice This function will only be called once.
    function _migrateBid(Bid memory mBid) internal {
        bids.push(mBid); // add the bid to the array
    }
}
