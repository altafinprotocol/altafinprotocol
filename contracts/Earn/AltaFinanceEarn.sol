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

    /// Number of days of interest kept in this smart contract upon Earn creation
    uint256 public reserveDays = 7;

    /// Percent of bid amount transferred to Alta Finance as a service fee (100 = 10%)
    uint256 public transferFee; // 100 = 10%

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

    /// @param bidder Address of the bidder
    /// @param bidId Index of bid in bids
    event BidMade(address indexed bidder, uint256 bidId);

    /// @param earnContractId Index of earn contract in earnContracts
    event ContractForSale(uint256 earnContractId);

    /// @param earnContractId Index of earn contract in earnContracts
    event ContractOffMarket(uint256 earnContractId);

    constructor(
        IERC20 _USDC,
        IERC20 _ALTA,
        address _loanAddress
    ) {
        USDC = _USDC;
        ALTA = _ALTA;
        loanAddress = _loanAddress;
        transferFee = 0;
    }

    enum ContractStatus {
        OPEN,
        CLOSED,
        FORSALE
    }

    struct EarnTerm {
        uint256 time; // Time Locked (in Days);
        uint16[] tokens; // Accepted Tokens
        uint16 interestRate; // Base APR (simple interest) (1000 = 10%)
        uint64 altaRatio; // ALTA ratio
        bool open; // True if open, False if closed
    }

    struct EarnContract {
        address owner; // Contract Owner Address
        uint256 termIndex; // Index of Earn Term
        uint256 startTime; // Unix Epoch time started
        uint256 contractLength; // length of contract in seconds
        uint256 lentAmount; // Amount of token lent
        uint256 baseTokenPaid; // Base Interest Paid
        uint256 altaPaid; // ALTA Interest Paid
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

     /// @param _time Length of the contract in days
     /// @param _token Token to lend
     /// @param _interestRate Base interest rate (1000 = 10%)
     /// @param _altaRatio Interest rate for ALTA (1000 = 10%)
     /// @dev Add an earn term with 8 parameters
    function addTerm(
        uint256 _time,
        address _token,
        uint16 _interestRate,
        uint64 _altaRatio,
    ) public onlyOwner {
        earnTerms.push(
            EarnTerm(
                _time,
                _token,
                _interestRate,
                _altaRatio,
                true
            )
        );
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
        if (earnTerms.length > 0) {
            return earnTerms;
        }
        return [];
    }

    /// @return An array of type Bid
    function getAllBids() public view returns (Bid[] memory) {
        if (bids.length > 0) {
            return bids;
        }
        return [];
    }

    /// Sends erc20 token to AltaFin Treasury Address and creates a contract with EarnContract[_id] terms for user.
    /// @param _earnTermsId index of the earn term in earnTerms
    /// @param _amount Amount of token to be swapped for USDC principal
    /// @param _swapTarget Address of the swap target
    /// @param _swapCallData Data to be passed to the swap target
    function openContract(
        uint256 _earnTermsId,
        uint256 _amount,
    ) public whenNotPaused {
        require(_amount > 0, "Token amount must be greater than zero");

        EarnTerm memory earnTerm = earnTerms[_earnTermsId];
        require(earnTerm.open, "Earn Term must be open");

        IERC20 Token = earnTerm.token;

        // User needs to first approve the token to be spent
        require(
            Token.balanceOf(address(msg.sender)) >= _amount,
            "Insufficient Tokens"
        );

        
        Token.safeTransferFrom(msg.sender, loanAddress, _amount);

        // Convert time of earnTerm from days to seconds
        uint256 earnSeconds = earnTerm.time * 1 days;

        _createContract(_earnTermsId, earnSeconds, _amount);
    }

    /// @param _earnTermsId index of the earn term in earnTerms
    /// @param _earnSeconds Length of the contract in seconds
    /// @param _lentAmount Amount of token lent
    function _createContract(
        uint256 _earnTermsId,
        uint256 _earnSeconds,
        uint256 _lentAmount
    ) internal {
        EarnContract memory earnContract = EarnContract(
            msg.sender, // owner
            _earnTermsId, // termIndex
            block.timestamp, // startTime
            _earnSeconds, //contractLength,
            _lentAmount, // lentAmount
            0, // baseTokenPaid
            0, // altaPaid
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
        (
            uint256 baseTokenAmount,
            uint256 altaAmount
        ) = redeemableValue(_earnContractId);
        earnContract.baseTokenPaid =
            earnContract.baseTokenPaid +
            baseTokenAmount;
        earnContract.altaPaid =
            earnContract.altaPaid +
            altaAmount;

        if (block.timestamp >= earnContract.startTime + earnContract.contractLength) {
            closeContract(_earnContractId);
        }

        IERC20 Token = earnTerms[earnContract.termIndex].token;
        Token.safeTransfer(msg.sender, baseTokenAmount);
        ALTA.safeTransfer(msg.sender, altaAmount);
    }

    function redeemAll() public {
        for (uint256 i = 0; i < earnContracts.length; i++) {
            if (earnContracts[i].owner == msg.sender) {
                redeem(i);
            }
        }
    }

    /// @param _earnContractId index of earn contract in earnContracts
    function closeContract(uint256 _earnContractId) internal {
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

    /// @dev calculate the currrent base token + ALTA interest available for the contract
    /// @param _earnContractId index of earn contract in earnContracts
    /// @return baseInterestAmount Base token interest amount
    /// @return altaInterestAmount ALTA interest amount
    function redeemableValue(uint256 _earnContractId)
        public
        view
        returns (uint256 baseTokenAmount, uint256 altaAmount)
    {
        EarnContract memory earnContract = earnContracts[_earnContractId];
        EarnTerm memory earnTerm = earnTerms[earnContract.termIndex];

        uint256 timeOpen = block.timestamp -
            earnContracts[_earnContractId].startTime;

       
        if (timeOpen <= earnContract.contractLength) {  // Just interest
            baseTokenAmount =
                (earnContract.lentAmount *
                    earnTerm.interestRate *
                    timeOpen) /
                365 days /
                10000;

            // Calculate the total amount of alta rewards accrued
            altaAmount = (((earnContract.lentAmount *
                earnTerm.altaRatio) / 10000) *
                (timeOpen / earnContract.contractLength));
        } else { // Principal + interest
            uint256 extraTime = timeOpen - earnContract.contractLength;

            // Calculate the total amount of usdc to be paid out (principal + interest)
            uint256 baseRegInterest = earnContract.lentAmount +
                ((earnContract.lentAmount *
                    earnTerm.interestRate *
                    earnContract.contractLength) /
                    365 days /
                    10000);

            baseTokenAmount = baseRegInterest + earnContract.baseTokenPrincipal;

            // Calculate the total amount of alta rewards accrued
            altaAmount = ((earnContract.lentAmount *
                earnTerm.altaRatio) / 10000);
        }

        baseTokenAmount = baseTokenAmount - earnContract.baseTokenPaid;
        altaAmount = altaAmount - earnContract.altaPaid;
        return (baseTokenAmount, altaAmount);
    }

    /// @dev calculate the currrent base token + ALTA interest available for the contract
    /// @param _earnContractId index of earn contract in earnContracts
    /// @return baseInterestAmount Base token interest amount
    /// @return altaInterestAmount ALTA interest amount
    function redeemableValue(uint256 _earnContractId, uint256 _time)
        public
        view
        returns (uint256 baseTokenAmount, uint256 altaAmount)
    {
        require (_time >= earnContracts[_earnContractId].startTime);
        EarnContract memory earnContract = earnContracts[_earnContractId];
        EarnTerm memory earnTerm = earnTerms[earnContract.termIndex];

        uint256 timeOpen = _time -
            earnContracts[_earnContractId].startTime;
       
        if (timeOpen <= earnContract.contractLength) {  // Just interest
            baseTokenAmount =
                (earnContract.lentAmount *
                    earnTerm.interestRate *
                    timeOpen) /
                365 days /
                10000;

            // Calculate the total amount of alta rewards accrued
            altaAmount = (((earnContract.lentAmount *
                earnTerm.altaRatio) / 10000) *
                (timeOpen / earnContract.contractLength));
        } else { // Principal + interest
            uint256 extraTime = timeOpen - earnContract.contractLength;

            // Calculate the total amount of usdc to be paid out (principal + interest)
            uint256 baseRegInterest = earnContract.lentAmount +
                ((earnContract.lentAmount *
                    earnTerm.interestRate *
                    earnContract.contractLength) /
                    365 days /
                    10000);

            baseTokenAmount = baseRegInterest + earnContract.baseTokenPrincipal;

            // Calculate the total amount of alta rewards accrued
            altaAmount = ((earnContract.lentAmount *
                earnTerm.altaRatio) / 10000);
        }

        baseTokenAmount = baseTokenAmount - earnContract.baseTokenPaid;
        altaAmount = altaAmount - earnContract.altaPaid;
        return (baseTokenAmount, altaAmount);
    }

    /// @dev calculate the currrent USDC held in the contract
    /// @param _lentAmount Base token principal amount
    /// @param _interestRate Base interest rate
    /// @return usdcInterestAmount USDC interest amount to be reserved in this contract upon Earn creation
    function redeemableValueReserves(
        uint256 _lentAmount,
        uint256 _interestRate
    ) public view returns (uint256 baseInterestAmount) {
        // Calculate the amount of usdc to be kept in address(this) upon earn contract creation
        usdcInterestAmount =
            (_lentAmount * _interestRate * reserveDays) /
            365 days /
            10000;
        return baseInterestAmount;
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
        Bid[] memory allBids = getAllBids(); //BUG: this reverts if there are no bids!

        if (allBids.length > 0) {
            for (uint256 i = allBids.length - 1; i >= 0; --i) {
                if (allBids[i].earnContractId == _earnContractId) {
                    if (allBids[i].accepted != true) {
                        ALTA.safeTransfer(allBids[i].bidder, allBids[i].amount);
                    }
                    _removeBid(i);
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

    /// @param _contracts Array of contracts to be migrated
    /// @param _terms Array of terms to be migrated
    /// @notice This function can only be called once.
    function migration(EarnContract[] memory _contracts, EarnTerm[] memory _terms) external onlyOwner {
        require(migrated == false, "Contract has already been migrated");
        for (uint256 i = 0; i < _contracts.length; i++) {
            _migrateContract(_contracts[i]);
        }
        for (uint256 i = 0; i < _terms.length; i++) {
            _migrateTerm(_terms[i]);
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
    function _migrateTerms(EarnTerm memory mTerm) internal {
        earnTerms.push(mTerm); // add the term to the array
    }
}
