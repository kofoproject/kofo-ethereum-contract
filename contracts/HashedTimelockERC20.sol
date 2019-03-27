pragma solidity ^0.4.23;
pragma experimental "v0.5.0";

import "./ERC20.sol";
import "./SafeMath.sol";

contract HashedTimelockERC20 {

    using SafeMath for uint;

    address internal admin;
    address internal feeAccount;
    uint internal feeRate;// percentage times (1 ether), wei

    struct SpecialFeeRate {
        bool isSpecial;
        uint specialFeeRate;
    }
    struct Lock{
        address sender;
        address receiver;
        address tokenContract;
        uint amount;
        bytes32 hValue;
        //超过此高度只能赎回，不能取现
        uint nLockNum;
        bool withdrawn;
        bool refunded;
        string preimage;
    }

    mapping(address => SpecialFeeRate) internal specialFeeRates;
    // @see HashedTimelock
    mapping(bytes32 => Lock) locks;

    constructor(address feeAccount_, uint feeRate_) public {
        require(feeAccount_ != address(0), "feeAccount illegal");
        require(feeRate_ <= 1e18, "feeRate illegal");
        admin = msg.sender;
        feeAccount = feeAccount_;
        feeRate = feeRate_;
    }

    // 事件定义
    event LogERC20Lock(
        bytes32 indexed lockId,
        address indexed sender,
        address indexed receiver,
        address tokenContract,
        uint amount,
        bytes32 hValue,
    //超过此高度只能赎回，不能取现
        uint nLockNum
    );
    event LogERC20Withdraw(bytes32 indexed lockId, string preimage);
    event LogERC20Refund(bytes32 indexed lockId);

    /// Check whether the msg.sender is admin
    modifier isAdmin() {
        require(msg.sender == admin);
        _;
    }

    // 校验逻辑：转账金额 小于 代币上发送者授权当前合约的额度
    modifier tokensTransferable(address _token, address _sender, uint _amount) {
        require(_amount > 0, "amount must be greater than zero ");
        require(ERC20(_token).allowance(_sender, this) >= _amount, "amount must be approve");
        _;
    }

    // @see HashedTimelock
    modifier validLockNum(uint _nLockNum) {
        require(_nLockNum > block.number, "nLockNum must be greater than current blockNum");
        _;
    }

    /**
     * 查询锁定是否存在
     */
    modifier lockExists(bytes32 _lockId) {
        require(haveLock(_lockId), "no lock for this lockId");
        _;
    }

    // @see HashedTimelock
    modifier lockMatches(bytes32 _lockId, string _preimage) {
        require(locks[_lockId].hValue == sha256(abi.encodePacked(sha256(abi.encodePacked(_preimage)))), "preimage error");
        _;
    }

    // @see HashedTimelock
    modifier withdrawable(bytes32 _lockId) {
        require(locks[_lockId].withdrawn == false, "lock is already withdraw");
        require(locks[_lockId].nLockNum > block.number, "blockNum is already greater than nLockNum");
        _;
    }

    // @see HashedTimelock
    modifier refundable(bytes32 _lockId) {
        require(locks[_lockId].refunded == false, "lock is already refund");
        require(locks[_lockId].withdrawn == false, "lock is already withdraw");
        require(locks[_lockId].nLockNum <= block.number, "blockNum is less than nLockNum");
        _;
    }

    /// Check the whether the msg.sender can lock
    modifier validlockInvoker(address _sender) {
        require(msg.sender==_sender || isSpecialAddress(msg.sender), "msg.sender not allowed to lock");
        _;
    }

    /// Get the admin address
    function getAdmin() external view returns (address) {
        return admin;
    }

    /// Get the feeAccount address
    function getFeeAccount() external view returns (address) {
        return feeAccount;
    }

    /// Get the feeRate
    function getFeeRate() external view returns (uint) {
        return feeRate;
    }

    /// Changes the official admin address.
    function changeAdmin(address admin_) external isAdmin {
        require(admin_ != address(0));
        admin = admin_;
    }

    /// Check whether the address is special address
    function isSpecialAddress(address address_) public view returns (bool){
        if (specialFeeRates[address_].isSpecial) {
            return true;
        }
        return false;
    }

    /// Get the special feeRate
    function getSpecialFeeRate(address specialAddress_) public view returns (uint) {
        require(specialAddress_ != address(0));
        return (specialFeeRates[specialAddress_].specialFeeRate);
    }


    /// Update the special address
    function specialFeeRateUpdate(address specialAddress_, uint feeRate_) external isAdmin {
        require(specialAddress_ != address(0));
        require(feeRate_ <= 1e18, "feeRate illegal");
        specialFeeRates[specialAddress_].isSpecial = true;
        specialFeeRates[specialAddress_].specialFeeRate = feeRate_;
    }

    /// Delete the special address
    function specialAddressDelete(address specialAddress_) external isAdmin {
        require(specialAddress_ != address(0));
        specialFeeRates[specialAddress_].isSpecial = false;
        specialFeeRates[specialAddress_].specialFeeRate = 0;
    }

    /// Changes the account address that receives fees
    function changeFeeAccount(address feeAccount_) external isAdmin {
        require(feeAccount_ != address(0));
        feeAccount = feeAccount_;
    }

    /// Changes the fee rate
    function changeFeeRate(uint feeRate_) external isAdmin {
        require(feeRate_ <= 1e18, "feeRate illegal");
        feeRate = feeRate_;
    }

    // @see HashedTimelock
    function lock(
        address _sender,
        address _receiver,
        bytes32 _hValue,
        uint _nLockNum,
        address _tokenContract,
        uint _amount
    )
    external
    validlockInvoker(_sender)
    tokensTransferable(_tokenContract, _sender, _amount)
    validLockNum(_nLockNum)
    returns (bytes32 lockId)
    {
        lockId = sha256(
            abi.encodePacked(
                _sender,
                _receiver,
                _tokenContract,
                _amount,
                _hValue,
                _nLockNum
            ));


        if (haveLock(lockId))
            revert("There is no this lockId!");

        // This contract becomes the temporary owner of the tokens
        // ！！！！！ 将金额锁定到当前的合约上
        if (!ERC20(_tokenContract).transferFrom(_sender, this, _amount))
            revert("erc 20 transfer from error!");

        locks[lockId] = Lock(
            _sender,
            _receiver,
            _tokenContract,
            _amount,
            _hValue,
            _nLockNum,
            false,
            false,
            "0x0"
        );

        emit LogERC20Lock(
            lockId,
            msg.sender,
            _receiver,
            _tokenContract,
            _amount,
            _hValue,
            _nLockNum
        );
    }

    /**
     * 提现
     */
    function withdraw(bytes32 _lockId, string _preimage)
    external
    lockExists(_lockId)
    lockMatches(_lockId, _preimage)
    withdrawable(_lockId)
    returns (bool)
    {
        Lock storage c = locks[_lockId];
        c.preimage = _preimage;
        c.withdrawn = true;

        // 手续费转账转账
        uint fee = feeTransfer(c.tokenContract, c.amount);

        // 从当前合约转账给接收人
        ERC20(c.tokenContract).transfer(c.receiver, c.amount.sub(fee));
        emit LogERC20Withdraw(_lockId, _preimage);
        return true;
    }


    function refund(bytes32 _lockId)
    external
    lockExists(_lockId)
    refundable(_lockId)
    returns (bool)
    {
        Lock storage c = locks[_lockId];
        c.refunded = true;

        // 从当前合约转账给接收人
        ERC20(c.tokenContract).transfer(c.sender, c.amount);
        emit LogERC20Refund(_lockId);
        return true;
    }


    function getLock(bytes32 _lockId)
    external
    view
    returns (
        address sender,
        address receiver,
        address tokenContract,
        uint amount,
        bytes32 hValue,
        uint nLockNum,
        bool withdrawn,
        bool refunded,
        string preimage
    )
    {
        if (haveLock(_lockId) == false)
            return;
        Lock storage c = locks[_lockId];
        return (
        c.sender,
        c.receiver,
        c.tokenContract,
        c.amount,
        c.hValue,
        c.nLockNum,
        c.withdrawn,
        c.refunded,
        c.preimage
        );
    }

    function haveLock(bytes32 _lockId)
    internal
    view
    returns (bool exists)
    {
        exists = (locks[_lockId].sender != address(0));
    }

    /// Transfer fee from msg.sender to feeAccount
    function feeTransfer(address tokenContract_, uint amount_) private returns (uint){
        uint finalRate;
        if (isSpecialAddress(msg.sender)) {
            finalRate = getSpecialFeeRate(msg.sender);
        } else {
            finalRate = feeRate;
        }
        uint fee = amount_.mul(finalRate).div(1 ether);
        if (fee == 0){
            return 0;
        }
        ERC20(tokenContract_).transfer(feeAccount, fee);
        return fee;
    }
}
