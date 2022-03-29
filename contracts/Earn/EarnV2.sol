//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./EarnBase.sol";

contract EarnV2 is EarnBase {
    using SafeERC20 for IERC20;

    IERC20 public ALTA;
    IERC20 public USDC;
    address loanAddress;
    address feeAddress;

    // Interest Bonus based off time late
    uint256 public baseBonusMultiplier;
    uint256 public altaBonusMultiplier;

    uint256 public transferFee;
    uint256 reserveDays;
    bool migrated = false;

    // List of all events emitted by the contract
    event ContractOpened(address indexed owner, uint256 earnContractId);
    event ContractClosed(address indexed owner, uint256 earnContractId);
    event EarnContractOwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner,
        uint256 earnContractId
    );
    event BidMade(address indexed bidder, uint256 bidId);
    event ContractForSale(uint256 earnContractId);
    event ContractOffMarket(uint256 earnContractId);

    constructor(
        IERC20 _USDC,
        IERC20 _ALTA,
        address _loanAddress,
        address _feeAddress
    ) {
        USDC = _USDC;
        ALTA = _ALTA;
        baseBonusMultiplier = 150; //150 = 1.5x
        altaBonusMultiplier = 200; // 200 = 2x
        reserveDays = 7;
        loanAddress = _loanAddress;
        feeAddress = _feeAddress;
    }

    enum ContractStatus {
        OPEN,
        CLOSED,
        FORSALE
    }

    struct EarnTerm {
        // Time Locked (in Days);
        uint256 time;
        // USDC APR (simple interest) (1000 = 10%)
        uint16 usdcRate;
        // ALTA ratio
        uint64 altaRatio;
        // Max usdc accepted
        uint256 usdcMax;
        // Amount already accepted
        uint256 usdcAccepted;
        // True if open, False if closed
        bool open;
    }

    struct EarnContract {
        // Contract Owner Address
        address owner;
        // Unix Epoch time started
        uint256 startTime;
        // length of contract in seconds
        uint256 contractLength;
        // Amount of ALTA lent
        uint256 altaAmount;
        // Amount sent to contract in USDC (swap value);
        uint256 usdcPrincipal;
        // USDC interest rate
        uint256 usdcRate;
        // USDC Interest Paid
        uint256 usdcInterestPaid;
        // ALTA interet rate
        uint256 altaRatio;
        // ALTA Interest Paid
        uint256 altaInterestPaid;
        // Rate usdc interest will be paid for days overdue
        uint256 usdcBonusRate;
        // Fixed ALTA bonus for overdue payment
        uint256 altaBonusRatio;
        // Open, Closed, or ForSale
        ContractStatus status;
    }

    struct Bid {
        // Bid Owner Address
        address bidder;
        // Address of Contract Owner
        address to;
        // Earn Contract Id
        uint256 earnContractId;
        // Amount
        uint256 amount;
        // Accepted - false if pending
        bool accepted;
    }

    // Comes with a public getter function
    EarnTerm[] public earnTerms;
    EarnContract[] public earnContracts;
    Bid[] public bids;

    // Maps the earn contract id to the owner
    mapping(uint256 => address) public earnContractToOwner;

    // Maps the number of earn contracts for a given user
    mapping(address => uint256) public ownerEarnContractCount;

    // Maps the number of bids per earn contract
    mapping(uint256 => uint256) public earnContractBidCount;

    /**
     * @param _time Length of the contract in days
     * @param _usdcRate Interest rate for USDC (1000 = 10%)
     * @param _altaRatio Interest rate for ALTA (1000 = 10%)
     * @dev Add an earn term with 8 parameters
     */
    function addTerm(
        uint256 _time,
        uint16 _usdcRate,
        uint64 _altaRatio,
        uint256 _usdcMax
    ) public onlyOwner {
        earnTerms.push(
            EarnTerm(_time, _usdcRate, _altaRatio, _usdcMax, 0, true)
        );
    }

    /**
     * Close an earn term
     * @param _earnTermsId index of the earn term in earnTerms
     */
    function closeTerm(uint256 _earnTermsId) public onlyOwner {
        _closeTerm(_earnTermsId);
    }

    /**
     * @param _earnTermsId index of the earn term in earnTerms
     * @dev Close an earn term
     */
    function _closeTerm(uint256 _earnTermsId) internal {
        require(_earnTermsId < earnTerms.length);
        earnTerms[_earnTermsId].open = false;
    }

    /**
     * Close an earn term
     * @param _earnTermsId index of the earn term in earnTerms
     */
    function openTerm(uint256 _earnTermsId) public onlyOwner {
        require(_earnTermsId < earnTerms.length);
        earnTerms[_earnTermsId].open = true;
    }

    /**
     * @dev Update an earn term passing the individual parameters
     * @param _earnTermsId index of the earn term in earnTerms
     * @param _time Length of the contract in days
     * @param _usdcRate Interest rate for USDC (1000 = 10%)
     */
    function updateTerm(
        uint256 _earnTermsId,
        uint256 _time,
        uint16 _usdcRate,
        uint64 _altaRatio,
        uint256 _usdcMax,
        uint256 _usdcAccepted,
        bool _open
    ) public onlyOwner {
        earnTerms[_earnTermsId] = EarnTerm(
            _time,
            _usdcRate,
            _altaRatio,
            _usdcMax,
            _usdcAccepted,
            _open
        );
    }

    /**
     * @notice Use the public getter function for earnTerms for a single earnTerm
     * @return An array of type EarnTerm
     */
    function getAllEarnTerms() public view returns (EarnTerm[] memory) {
        return earnTerms;
    }

    /**
     * @notice Use the public getter function for earnTerms for a single earnTerm
     * @return An array of type EarnTerm with open == true
     */
    function getAllOpenEarnTerms() public view returns (EarnTerm[] memory) {
        EarnTerm[] memory result = new EarnTerm[](earnTerms.length);
        uint256 counter = 0;

        for (uint256 i = 0; i < earnTerms.length; i++) {
            if (earnTerms[i].open == true) {
                result[counter] = earnTerms[i];
                counter++;
            }
        }
        return result;
    }

    /**
     * @notice Use the public getter function for bids for a sinble bid
     * @return An array of type Bid
     */
    function getAllBids() public view returns (Bid[] memory) {
        return bids;
    }

    /**
     * Sends erc20 token to AltaFin Treasury Address and creates a contract with EarnContract[_id] terms for user.
     * @param _earnTermsId index of the earn term in earnTerms
     * @param _amount Amount of token to be swapped for USDC principal
     * @param _swapTarget Address of the swap target
     * @param _swapCallData Data to be passed to the swap target
     */
    function openContract(
        uint256 _earnTermsId,
        uint256 _amount,
        address _swapTarget,
        bytes calldata _swapCallData
    ) public whenNotPaused {
        require(_amount > 0, "Token amount must be greater than zero");
        // User needs to first approve the token to be spent
        require(
            ALTA.balanceOf(address(msg.sender)) >= _amount,
            "Insufficient Tokens"
        );

        EarnTerm memory earnTerm = earnTerms[_earnTermsId];
        require(earnTerm.open, "Earn Term must be open");

        ALTA.safeTransferFrom(msg.sender, address(this), _amount);

        // Swap tokens for USDC
        uint256 amountUsdc = _swapToUSDCOnZeroX(
            _earnTermsId,
            _amount,
            payable(_swapTarget), // address payable swapTarget
            _swapCallData // bytes calldata swapCallData
        );

        earnTerms[_earnTermsId].usdcAccepted =
            earnTerms[_earnTermsId].usdcAccepted +
            amountUsdc;

        // New Contract can't be created if usdcAccepted will exceed usdcMax by more than 10%
        require(
            earnTerms[_earnTermsId].usdcAccepted <=
                (earnTerms[_earnTermsId].usdcMax +
                    (earnTerms[_earnTermsId].usdcMax / 10)),
            "usdc amount greater than max"
        );

        // Close the earn term if usdcAccepted will exceed usdcMax
        if (
            earnTerms[_earnTermsId].usdcAccepted >=
            earnTerms[_earnTermsId].usdcMax
        ) {
            _closeTerm(_earnTermsId);
        }

        // Convert time of earnTerm from days to seconds
        uint256 earnSeconds = earnTerm.time * 1 days;

        _createContract(earnTerm, earnSeconds, amountUsdc, _amount);
    }

    /**
     * @param _earnTerm EarnTerm object used to create contract
     * @param _earnSeconds Length of the contract in seconds
     * @param _amountUsdc Amount of USDC principal
     * @param _amountAlta Amount of ALTA lent to the contract
     */
    function _createContract(
        EarnTerm memory _earnTerm,
        uint256 _earnSeconds,
        uint256 _amountUsdc,
        uint256 _amountAlta
    ) internal {
        EarnContract memory earnContract = EarnContract(
            msg.sender, // owner
            block.timestamp, // startTime
            _earnSeconds, //contractLength,
            _amountAlta, // altaAmount
            _amountUsdc, // usdcPrincipal
            _earnTerm.usdcRate, // usdcRate
            0, // usdcInterestPaid
            _earnTerm.altaRatio, // altaRatio
            0, // altaInterestPaid
            (_earnTerm.usdcRate * baseBonusMultiplier) / 100, // usdcBonusRate
            (_earnTerm.altaRatio * altaBonusMultiplier) / 100, // altaBonusRatio
            ContractStatus.OPEN
        );

        earnContracts.push(earnContract);
        uint256 id = earnContracts.length - 1;
        earnContractToOwner[id] = msg.sender; // assign the earn contract to the owner;
        ownerEarnContractCount[msg.sender] =
            ownerEarnContractCount[msg.sender] +
            1; // increment the number of earn contract owned for the user;
        emit ContractOpened(msg.sender, id);
    }

    /**
     * Sends the amount usdc and alta owed to the contract owner and deletes the EarnContract from the mapping.
     * @param _earnContractId index of earn contract in earnContracts
     */
    function closeContract(uint256 _earnContractId) external onlyOwner {
        require(
            earnContracts[_earnContractId].status != ContractStatus.CLOSED,
            "Contract is already closed"
        );
        (uint256 usdcAmount, uint256 altaAmount) = _calculatePaymentAmounts(
            _earnContractId
        );

        address owner = earnContracts[_earnContractId].owner;

        USDC.safeTransferFrom(msg.sender, address(owner), usdcAmount);
        ALTA.safeTransferFrom(msg.sender, address(owner), altaAmount);

        emit ContractClosed(owner, _earnContractId);

        _removeAllContractBids(_earnContractId);

        // Mark the contract as closed
        require(
            _earnContractId < earnContracts.length,
            "Contract Index not in the array"
        );

        earnContracts[_earnContractId].status = ContractStatus.CLOSED;
    }

    /**
     * Internal function to calculate the amount of USDC and ALTA needed to close an earnContract
     * @param _earnContractId index of earn contract in earnContracts
     */
    function _calculatePaymentAmounts(uint256 _earnContractId)
        internal
        view
        returns (uint256 usdcAmount, uint256)
    {
        EarnContract memory earnContract = earnContracts[_earnContractId];
        (
            uint256 usdcInterestAmount,
            uint256 altaInterestAmount
        ) = calculateInterest(_earnContractId);
        usdcAmount = earnContract.usdcPrincipal + usdcInterestAmount;
        return (usdcAmount, altaInterestAmount);
    }

    /**
     * @dev redeem the currrent USDC + ALTA interest available for the contract
     * @param _earnContractId index of earn contract in earnContracts
     */
    function redeemInterest(uint256 _earnContractId) public {
        EarnContract memory earnContract = earnContracts[_earnContractId];
        require(earnContract.owner == msg.sender);
        (
            uint256 usdcInterestAmount,
            uint256 altaInterestAmount
        ) = calculateInterest(_earnContractId);
        earnContract.usdcInterestPaid =
            earnContract.usdcInterestPaid +
            usdcInterestAmount;
        earnContract.altaInterestPaid =
            earnContract.altaInterestPaid +
            altaInterestAmount;

        USDC.safeTransfer(msg.sender, usdcInterestAmount);
        ALTA.safeTransfer(msg.sender, altaInterestAmount);
    }

    /**
     * @dev calculate the currrent USDC + ALTA interest available for the contract
     * @param _earnContractId index of earn contract in earnContracts
     */
    function calculateInterest(uint256 _earnContractId)
        public
        view
        returns (uint256 usdcInterestAmount, uint256 altaInterestAmount)
    {
        EarnContract memory earnContract = earnContracts[_earnContractId];
        uint256 timeOpen = block.timestamp -
            earnContracts[_earnContractId].startTime;

        // 7 day buffer for Alta Finance to pay back contract
        if (timeOpen <= earnContract.contractLength + 7 days) {
            // Calculate the total amount of usdc to be paid out (principal + interest)
            usdcInterestAmount =
                (earnContract.usdcPrincipal *
                    earnContract.usdcRate *
                    timeOpen) /
                365 days /
                10000;

            // Calculate the total amount of alta rewards accrued
            altaInterestAmount = (((earnContract.usdcPrincipal *
                earnContract.altaRatio) / 10000) *
                (timeOpen / earnContract.contractLength));
        } else {
            // Interest Bonus Rate is in effect 7 days after contract maturity
            uint256 extraTime = timeOpen - earnContract.contractLength;

            // Calculate the total amount of usdc to be paid out (principal + interest)
            uint256 usdcRegInterest = earnContract.usdcPrincipal +
                ((earnContract.usdcPrincipal *
                    earnContract.usdcRate *
                    earnContract.contractLength) /
                    365 days /
                    10000);

            uint256 usdcBonusInterest = (earnContract.usdcPrincipal *
                earnContract.usdcBonusRate *
                extraTime) /
                365 days /
                10000;
            usdcInterestAmount = usdcRegInterest + usdcBonusInterest;

            // Calculate the total amount of alta rewards accrued
            altaInterestAmount = (((earnContract.usdcPrincipal *
                earnContract.altaBonusRatio) / 10000) *
                (timeOpen / earnContract.contractLength));
        }

        // Subtract the interest that has already been paid out on the contract
        usdcInterestAmount = usdcInterestAmount - earnContract.usdcInterestPaid;
        altaInterestAmount = altaInterestAmount - earnContract.altaInterestPaid;
        return (usdcInterestAmount, altaInterestAmount);
    }

    /**
     * @dev calculate the currrent USDC held in the contract
     * @param _usdcPrincipal USDC principal amount
     * @param _usdcRate USDC interest rate
     */
    function calculateInterestReserves(
        uint256 _usdcPrincipal,
        uint256 _usdcRate
    ) public view returns (uint256 usdcInterestAmount) {
        // Calculate the amount of usdc to be kept in address(this) upon earn contract creation
        usdcInterestAmount =
            (_usdcPrincipal * _usdcRate * reserveDays) /
            365 days /
            10000;
        return usdcInterestAmount;
    }

    /**
     * Gets the current value of all earn terms for a given user
     * @param _owner address of owner to query
     */
    function getCurrentUsdcValueByOwner(address _owner)
        public
        view
        returns (uint256)
    {
        uint256[] memory result = getContractsByOwner(_owner);
        uint256 currValue = 0;

        for (uint256 i = 0; i < result.length; i++) {
            EarnContract memory earnContract = earnContracts[result[i]];
            if (earnContract.status != ContractStatus.CLOSED) {
                uint256 timeHeld = (block.timestamp - earnContract.startTime) /
                    365 days;
                currValue =
                    currValue +
                    earnContract.usdcPrincipal +
                    (earnContract.usdcPrincipal *
                        earnContract.usdcRate *
                        timeHeld);
            }
        }
        return currValue;
    }

    /**
     * Gets the value at time of redemption for all earns terms for a given user
     * @param _owner address of owner to query
     */
    function getRedemptionUsdcValueByOwner(address _owner)
        public
        view
        returns (uint256)
    {
        uint256[] memory result = getContractsByOwner(_owner);
        uint256 currValue = 0;

        for (uint256 i = 0; i < result.length; i++) {
            EarnContract memory earnContract = earnContracts[result[i]];
            if (earnContract.status != ContractStatus.CLOSED) {
                currValue =
                    currValue +
                    earnContract.usdcPrincipal +
                    (
                        ((earnContract.usdcPrincipal *
                            earnContract.usdcRate *
                            earnContract.contractLength) / 365 days)
                    );
            }
        }
        return currValue;
    }

    /**
     * Gets every earn contract for a given user
     * @param _owner Wallet Address for expected earn contract owner
     */
    function getContractsByOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory result = new uint256[](ownerEarnContractCount[_owner]);
        uint256 counter = 0;
        for (uint256 i = 0; i < earnContracts.length; i++) {
            if (earnContractToOwner[i] == _owner) {
                result[counter] = i;
                counter++;
            }
        }
        return result;
    }

    /**
     * gets all earn contracts
     */
    function getAllEarnContracts() public view returns (EarnContract[] memory) {
        return earnContracts;
    }

    /**
     * Swaps ERC20->ERC20 tokens held by this contract using a 0x-API quote.
     * @param _swapTarget 'To' field from the 0x API response
     * @param _swapCallData 'Data' field from the 0x API response
     */
    function _swapToUSDCOnZeroX(
        uint256 _earnTermId,
        uint256 _amount,
        // The `to` field from the API response.
        address payable _swapTarget,
        // The `data` field from the API response.
        bytes calldata _swapCallData
    ) internal returns (uint256) {
        uint256 currentUsdcBalance = USDC.balanceOf(address(this));

        require(ALTA.approve(_swapTarget, _amount), "approve failed");

        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        (bool success, ) = _swapTarget.call{value: msg.value}(_swapCallData);
        require(success, "SWAP_CALL_FAILED");

        uint256 usdcAmount = USDC.balanceOf(address(this)) - currentUsdcBalance;
        uint256 interestReserve = calculateInterestReserves(
            usdcAmount,
            earnTerms[_earnTermId].usdcRate
        );
        uint256 amount = usdcAmount - interestReserve;
        USDC.safeTransfer(loanAddress, amount);
        return usdcAmount;
    }

    /**
     * Lists the associated earn contract for sale on the market
     * @param _earnContractId index of earn contract in earnContracts
     */
    function putSale(uint256 _earnContractId) external whenNotPaused {
        require(
            msg.sender == earnContractToOwner[_earnContractId],
            "Msg.sender is not the owner"
        );
        earnContracts[_earnContractId].status = ContractStatus.FORSALE;
        emit ContractForSale(_earnContractId);
    }

    /**
     * Submits a bid for an earn contract on sale in the market
     * User must sign an approval transaction for first. ALTA.approve(address(this), _amount);
     * @param _earnContractId index of earn contract in earnContracts
     * @param _amount Amount of ALTA offered for bid
     */
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
        earnContractBidCount[_earnContractId] =
            earnContractBidCount[_earnContractId] +
            1; // increment the number of bids for the earn contract;

        // Send the bid amount to this contract
        ALTA.safeTransferFrom(msg.sender, address(this), _amount);
        emit BidMade(msg.sender, bidId);
    }

    /**
     * Called by the owner of the earn contract for sale
     * Transfers the bid amount to the owner of the earn contract and transfers ownership of the contract to the bidder
     * @param _bidId index of bid in Bids
     */
    function acceptBid(uint256 _bidId) external whenNotPaused {
        Bid memory bid = bids[_bidId];
        uint256 earnContractId = bid.earnContractId;

        uint256 fee = (bid.amount * transferFee) / 1000;
        if (fee > 0) {
            bid.amount = bid.amount - fee;
        }

        // Transfer bid ALTA to contract seller
        require(
            msg.sender == earnContractToOwner[earnContractId],
            "Msg.sender is not the owner of the earn contract"
        );
        if (fee > 0) {
            ALTA.safeTransfer(feeAddress, fee);
            bid.amount = bid.amount - fee;
        }
        ALTA.safeTransfer(bid.to, bid.amount);

        bids[_bidId].accepted = true;

        // Transfer ownership of earn contract to bidder
        emit EarnContractOwnershipTransferred(
            bid.to,
            bid.bidder,
            earnContractId
        );
        earnContracts[earnContractId].owner = bid.bidder;
        earnContractToOwner[earnContractId] = bid.bidder;
        ownerEarnContractCount[bid.bidder] =
            ownerEarnContractCount[bid.bidder] +
            1;

        // Remove all bids
        _removeContractFromMarket(earnContractId);
    }

    /**
     * Remove Contract From Market
     * @param _earnContractId index of earn contract in earnContracts
     */
    function removeContractFromMarket(uint256 _earnContractId) external {
        require(
            earnContractToOwner[_earnContractId] == msg.sender,
            "Msg.sender is not the owner of the earn contract"
        );
        _removeContractFromMarket(_earnContractId);
    }

    /**
     * Removes all contracts bids and sets the status flag back to open
     * @param _earnContractId index of earn contract in earnContracts
     */
    function _removeContractFromMarket(uint256 _earnContractId) internal {
        earnContracts[_earnContractId].status = ContractStatus.OPEN;
        _removeAllContractBids(_earnContractId);
        emit ContractOffMarket(_earnContractId);
    }

    /**
     * Getter functions for all bids of a specified earn contract
     * @param _earnContractId index of earn contract in earnContracts
     */
    function getBidsByContract(uint256 _earnContractId)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory result = new uint256[](
            earnContractBidCount[_earnContractId]
        );
        uint256 counter = 0;
        for (uint256 i = 0; i < bids.length; i++) {
            if (bids[i].earnContractId == _earnContractId) {
                result[counter] = i;
                counter++;
            }
        }
        return result;
    }

    /**
     * Sends all bid funds for an earn contract back to the bidder and removes them arrays and mappings
     * @param _earnContractId index of earn contract in earnContracts
     */
    function _removeAllContractBids(uint256 _earnContractId) internal {
        uint256[] memory contractBids = getBidsByContract(_earnContractId);
        for (uint256 i = 0; i < contractBids.length; i++) {
            uint256 bidId = contractBids[0];
            Bid memory bid = bids[bidId];
            if (bid.accepted != true) {
                ALTA.safeTransfer(bid.bidder, bid.amount);
            }
            _removeBid(bidId);
        }
    }

    /**
     * Sends bid funds back to bidder and removes the bid from the array
     * @param _bidId index of bid in Bids
     */
    function removeBid(uint256 _bidId) external {
        Bid memory bid = bids[_bidId];
        require(msg.sender == bid.bidder, "Msg.sender is not the bidder");
        ALTA.safeTransfer(bid.bidder, bid.amount);

        _removeBid(_bidId);
    }

    /**
     * @param _bidId index of bid in Bids
     */
    function _removeBid(uint256 _bidId) internal {
        require(_bidId < bids.length, "Bid ID longer than array length");
        Bid memory bid = bids[_bidId];

        // Update the mappings
        uint256 earnContractId = bid.earnContractId;
        if (earnContractBidCount[earnContractId] > 0) {
            earnContractBidCount[earnContractId] =
                earnContractBidCount[earnContractId] -
                1;
        }

        // Update the array
        if (bids.length > 1) {
            bids[_bidId] = bids[bids.length - 1];
        }
        bids.pop();
    }

    /**
     * Set the transfer fee rate for contracts sold on the market place
     * @param _transferFee Percent of accepted earn contract bid to be sent to AltaFin wallet
     */
    function setTransferFee(uint256 _transferFee) external onlyOwner {
        transferFee = _transferFee;
    }

    /**
     * Set ALTA ERC20 token address
     * @param _ALTA Address of ALTA Token contract
     */
    function setAltaAddress(address _ALTA) external onlyOwner {
        ALTA = IERC20(_ALTA);
    }

    /**
     * Set the reserveDays
     * @param _reserveDays Number of days interest to be stored in address(this) upon contract creation
     */
    function setReserveDays(uint256 _reserveDays) external onlyOwner {
        reserveDays = _reserveDays;
    }

    /**
     * Set the Bonus USDC multiplier ( e.g. 20 = 2x multiplier on the interest rate)
     * @param _baseBonusMultiplier Base Bonus multiplier for contract left open after contract length completion
     */
    function setBaseBonusMultiplier(uint256 _baseBonusMultiplier)
        external
        onlyOwner
    {
        baseBonusMultiplier = _baseBonusMultiplier;
    }

    /**
     * Set the Bonus ALTA multiplier ( e.g. 20 = 2x multiplier on the ALTA Amount)
     * @param _altaBonusMultiplier ALTA Bonus multiplier for contract left open after contract length completion
     */
    function setAltaBonusMultiplier(uint256 _altaBonusMultiplier)
        external
        onlyOwner
    {
        altaBonusMultiplier = _altaBonusMultiplier;
    }

    /**
     * Set the loanAddress
     * @param _loanAddress Wallet address to recieve loan funds
     */
    function setLoanAddress(address _loanAddress) external onlyOwner {
        require(_loanAddress != address(0));
        loanAddress = _loanAddress;
    }

    /**
     * Set the feeAddress
     * @param _feeAddress Wallet address to recieve fee funds
     */
    function setFeeAddress(address _feeAddress) external onlyOwner {
        require(_feeAddress != address(0));
        feeAddress = _feeAddress;
    }

    /**
     * @param _migrated Array of contracts to be migrated
     * @notice This function can only be called once.
     */
    function migrateContracts(EarnContract[] memory _migrated)
        external
        onlyOwner
    {
        require(migrated == false, "Contract has already been migrated");
        for (uint256 i = 0; i < _migrated.length; i++) {
            _migrateContract(_migrated[i]);
        }
        migrated = true;
    }

    /**
     * @param mContract Contract to be migrated
     * @notice This function will only be called once.
     */
    function _migrateContract(EarnContract memory mContract) internal {
        EarnContract memory earnContract = EarnContract(
            mContract.owner, // owner
            mContract.startTime, // startTime
            mContract.contractLength, // contractLength,
            mContract.altaAmount, // altaAmount
            mContract.usdcPrincipal, // usdcPrincipal
            mContract.usdcRate, // usdcRate
            mContract.usdcInterestPaid, // usdcInterestPaid
            mContract.altaRatio, // altaRatio
            mContract.altaInterestPaid, // altaInterestPaid
            mContract.usdcBonusRate, // usdcBonusRate
            mContract.altaBonusRatio, // altaBonusRatio
            mContract.status // status
        );

        earnContracts.push(earnContract); // add the contract to the array
        uint256 id = earnContracts.length - 1; // get the id of the earnContract
        earnContractToOwner[id] = mContract.owner; // assign the earn contract to the owner;
        ownerEarnContractCount[mContract.owner] =
            ownerEarnContractCount[mContract.owner] +
            1; // increment the number of earn contract owned for the user;
        emit ContractOpened(mContract.owner, id); // emit the event
    }
}
