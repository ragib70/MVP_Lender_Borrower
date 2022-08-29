// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.7;
pragma abicoder v2;

import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/Counters.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

interface INft{
    function mint(uint256 amount, string memory _metadata) external returns(uint256);
    function sendtoReciepient(address recepient, uint256 id) external;
    function getCurTokenId() external view returns (uint256);
}

contract BankiFi {

    event TransferSent(address _from, address _destAddr, uint _amount);
    event BorrowerId(uint id, address borrowerAddress);
    event LenderId(uint id, address lenderAddress);
    // For the scope of these swap examples,
    // we will detail the design considerations when using
    // `exactInput`, `exactInputSingle`, `exactOutput`, and  `exactOutputSingle`.

    // It should be noted that for the sake of these examples, we purposefully pass in the swap router instead of inherit the swap router for simplicity.
    // More advanced example contracts will detail how to inherit the swap router safely.

    ISwapRouter public immutable swapRouter;

    using Counters for Counters.Counter;
    using SafeMath for uint256;
    Counters.Counter public _borrowerNum;
    Counters.Counter public _lenderNum;

    struct borrower {
      address borrowerAddress;
      uint256 amountDeposit;
      uint256 mappedLenderId;
      uint id;
      bool matched;
      uint256 installmentAmount;
      uint256 timeMonths;
      uint256 lastBlockTimeStamp;
      bool closure; // Tells whether the position is closed or not.
      uint256 installmentsLeft;
    }

    struct lender {
      address lenderAddress;
      uint256 amountDeposit;
      uint256 mappedBorrowerId;
      uint id;
      bool matched;
      uint256 installmentAmount;
      uint256 timeMonths;
      uint256 lastBlockTimeStamp;
      bool closure; // Tells whether the position is closed or not.
      uint256 installmentsLeft;
    }

    mapping (uint256 => borrower) public _borrowerList;
    mapping (uint256 => lender) public _lenderList;

   

    // This example swaps USDC/WETH for single path swaps and USDC/USDC/WETH for multi path swaps.

    address public constant DAI = 0xaD6D458402F60fD3Bd25163575031ACDce07538D;
    address public constant WETH = 0xc778417E063141139Fce010982780140Aa0cD5Ab;
    address public constant USDC = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F;

    // For this example, we will set the pool fee to 0.3%.
    uint24 public constant poolFee = 3000;

    constructor(ISwapRouter _swapRouter) {
        swapRouter = _swapRouter;
    }

    /// @notice swapExactInputSingle swaps a fixed amount of USDC for a maximum possible amount of WETH
    /// using the USDC/WETH 0.3% pool by calling `exactInputSingle` in the swap router.
    /// @dev The calling address must approve this contract to spend at least `amountIn` worth of its USDC for this function to succeed.
    /// @param amountIn The exact amount of USDC that will be swapped for WETH.
    /// @return amountOut The amount of WETH received.
    function swapExactInputSingle(uint256 amountIn) external returns (uint256 amountOut) {
        // msg.sender must approve this contract

        // Transfer the specified amount of USDC to this contract.
        // TransferHelper.safeTransferFrom(USDC, msg.sender, address(this), amountIn);

        // Approve the router to spend USDC.
        TransferHelper.safeApprove(USDC, address(swapRouter), amountIn);

        // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
        // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: USDC,
                tokenOut: WETH,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        // The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(params);
    }

    // NFT functions from here onwards.

    function mintNFT(address _NFTContract, uint256 amount, string memory _metadata, address _borrower, address _lender, uint256 _id) external {
        INft(_NFTContract).mint(amount, _metadata);
        INft(_NFTContract).sendtoReciepient(_borrower, _id);
        INft(_NFTContract).sendtoReciepient(_lender, _id);
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function onERC721Received(address, address, uint256, bytes memory) public virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // NFT functions ends here onwards.

    // Before caliing this function the borrower must approve the main contract to allow the contract to deposit the fund to itslef on behalf of borrower.
    function borrowerDeposit(IERC20 token, uint256 amount) public {
        amount = amount.mul(1000000); // Done for converting 1USD because 1 USDC = 1000000 units
        uint256 erc20balance = token.balanceOf(msg.sender);
        require(amount <= erc20balance, "balance is low");
        token.transferFrom(msg.sender, address(this), amount);
        emit TransferSent(msg.sender, address(this), amount);
        borrower memory curr;
        curr.borrowerAddress = msg.sender;
        curr.amountDeposit = amount;
        curr.id = _borrowerNum.current();
        curr.closure = false;
        _borrowerList[_borrowerNum.current()] = curr;
        emit BorrowerId(curr.id, curr.borrowerAddress);
        _borrowerNum.increment();
    }

    // Before caliing this function the lender must approve the main contract to allow the contract to deposit the fund to itslef on behalf of lender.
    function lenderDeposit(IERC20 token, uint256 amount) public {
        amount = amount.mul(1000000);// Done for converting 1USD because 1 USDC = 1000000 units
        uint256 erc20balance = token.balanceOf(msg.sender);
        require(amount <= erc20balance, "balance is low");
        token.transferFrom(msg.sender, address(this), amount);
        emit TransferSent(msg.sender, address(this), amount);
        lender memory curr;
        curr.lenderAddress = msg.sender;
        curr.amountDeposit = amount;
        curr.id = _lenderNum.current();
        curr.closure = false;
        _lenderList[_lenderNum.current()] = curr;
        emit LenderId(curr.id, curr.lenderAddress);
        _lenderNum.increment();
    }

    function matchBorrowerLender(uint256 id, address _NFTContract, string memory uri, uint256 _timeMonths) public{
        require(_borrowerList[id].borrowerAddress == msg.sender, "Incorrect Borrower");
        require(_borrowerList[id].matched == false, "Already matched");
        require(_borrowerList[id].closure == false, "Position already closed");
        uint256 i=0;
        for(i=0; i<_lenderNum.current(); i++){
            if(_lenderList[i].matched == false && _lenderList[i].amountDeposit == _borrowerList[id].amountDeposit){
                break;
            }
        }

        // If i == lenderNum, then in that case there has not been any match.
        require(i < _lenderNum.current(), "No matching lender available");

        uint256 amount = _borrowerList[id].amountDeposit;
        this.swapExactInputSingle(amount.mul(2));

        // Mint NFTs.
        uint256 currentNFTId = INft(_NFTContract).getCurTokenId();
        this.mintNFT(_NFTContract, 2, uri, _borrowerList[id].borrowerAddress, _lenderList[i].lenderAddress, currentNFTId);

        // Update the states.
        uint256 temp1 = _borrowerList[id].amountDeposit.div(10);
        uint256 temp2 = (11**_timeMonths);
        uint256 temp3 = temp1.mul(temp2);
        uint256 temp4 = (10**_timeMonths);
        uint256 temp5 = temp2.sub(temp4);
        uint256 installment = temp3.div(temp5); // Fixed for now need to plugin the value now.

        _borrowerList[id].mappedLenderId = i;
        _borrowerList[id].matched = true;
        _borrowerList[id].installmentAmount = installment;
        _borrowerList[id].timeMonths = _timeMonths;
        _borrowerList[id].lastBlockTimeStamp = block.timestamp;
        _borrowerList[id].installmentsLeft = _timeMonths;

        _lenderList[i].mappedBorrowerId = id;
        _lenderList[i].matched = true;
        _lenderList[i].installmentAmount = installment;
        _lenderList[i].timeMonths = _timeMonths;
        _lenderList[i].lastBlockTimeStamp = block.timestamp;
        _lenderList[i].installmentsLeft = _timeMonths;
    }    

    // The borrower should approve the contract to transfer funds on its behave in USDC.
    function PayInstallment(IERC20 token, uint256 id) public {
        require(_borrowerList[id].borrowerAddress == msg.sender, "Borrower Id Mismatch");
        require(_borrowerList[id].closure == false, "Position already closed");
        uint256 erc20balance = token.balanceOf(msg.sender);
        require(_borrowerList[id].installmentAmount <= erc20balance, "balance is low");
        uint256 _lenderId = _borrowerList[id].mappedLenderId;
        token.transferFrom(msg.sender, _lenderList[_lenderId].lenderAddress, _borrowerList[id].installmentAmount);
        emit TransferSent(msg.sender, _lenderList[_lenderId].lenderAddress, _borrowerList[id].installmentAmount);

        // Now update the states.
        // Decrement the installmentsLeft.
        _borrowerList[id].installmentsLeft = _borrowerList[id].installmentsLeft.sub(1);
        _lenderList[id].installmentsLeft = _lenderList[id].installmentsLeft.sub(1);
        if(_borrowerList[id].installmentsLeft == 0){
            _borrowerList[id].closure = true;
            _lenderList[id].closure = true;
        }

        // Update the timestamp.
        _borrowerList[id].lastBlockTimeStamp = block.timestamp;
        _lenderList[_lenderId].lastBlockTimeStamp = block.timestamp;
    } 

    // Correct Installment by Lender
    function CorrectInstallment(uint256 id) public{
        require(_lenderList[id].lenderAddress == msg.sender, "Lender Id Mismatch");
        require(_lenderList[id].closure == false, "Position already closed");
        uint256 _borrowerId = _lenderList[id].mappedBorrowerId;

        if(_lenderList[id].lastBlockTimeStamp >= 60 && _lenderList[id].lastBlockTimeStamp < 120){
            // Revise installment Amount.
            _borrowerList[_borrowerId].installmentAmount = 50; // Replace with a formula afterwards.
            _lenderList[id].installmentAmount = 50;
        }

        if(_lenderList[id].lastBlockTimeStamp >= 120){
            // Do the closure and transfer the weth - installment Paid to the lender.
            uint256 WETHbalance = IERC20(WETH).balanceOf(address(this));

            uint256 closureAmount = 100; // Replace with formula AmountDeposit - installmentAmount*(TimeMonths - InstallmentsLeft)
            require(closureAmount <= WETHbalance, "balance is low");

            IERC20(WETH).transfer(_lenderList[id].lenderAddress, closureAmount);
            _lenderList[id].closure = true;
            _borrowerList[_borrowerId].closure = true;
        }
    }

}