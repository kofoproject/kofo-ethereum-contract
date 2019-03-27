pragma solidity ^0.4.23;
pragma experimental "v0.5.0";

import "./SafeMath.sol";

contract HashedTimelock {

    using SafeMath for uint;

    address internal admin;
    address internal feeAccount;
    uint internal feeRate;// percentage times (1 ether), wei

    struct SpecialFeeRate {
        bool isSpecial;
        uint specialFeeRate;
    }
    // 锁结构体
    struct Lock {
        //发送方
        address sender;
        //接收方
        address receiver;
        //锁定金额
        uint amount;
        //锁定的h值
        bytes32 hValue;
        //超过此高度只能赎回，不能取现
        uint nLockNum;
        //是否取现
        bool withdrawn;
        //是否赎回
        bool refunded;
        //原始的s值
        string preimage;
    }

    // specialFeeRates
    mapping(address => SpecialFeeRate) internal specialFeeRates;
    // LockContract 容器
    mapping(bytes32 => Lock) locks;

    constructor(address feeAccount_, uint feeRate_) public {
        require(feeAccount_ != address(0), "feeAccount illegal");
        require(feeRate_ <= 1e18, "feeRate illegal");
        admin = msg.sender;
        feeAccount = feeAccount_;
        feeRate = feeRate_;
    }

    // 事件定义
    event LogLock(
        bytes32 indexed lockId,
        address indexed sender,
        address indexed receiver,
        uint amount,
        bytes32 hValue,
    //超过此高度只能赎回，不能取现
        uint nLockNum
    );

    //preimage 不能使用index，过长会有问题
    event LogWithdraw(bytes32 indexed lockId, string preimage);
    event LogRefund(bytes32 indexed lockId);

    /// Check whether the msg.sender is admin
    modifier isAdmin() {
        require(msg.sender == admin);
        _;
    }

    // 校验逻辑：金额不能为0
    modifier validAmount() {
        require(msg.value > 0, "amount should be over zero");
        _;
    }

    // 区块必须是将来的区块
    modifier validLockNum(uint _blockNum) {
        require(_blockNum > block.number, "nLockNum must be greater than current blockNum");
        _;
    }

    // 校验逻辑：参数所对应的合约必须存在
    modifier lockExists(bytes32 _lockId) {
        require(haveLock(_lockId), "no lock for this lockId");
        _;
    }

    // 校验逻辑：给定元素 _preimage 的 哈希值与合约Id所持有的hashLock值相等
    modifier lockMatches(bytes32 _lockId, string _preimage) {
        require(locks[_lockId].hValue == sha256(abi.encodePacked(sha256(abi.encodePacked(_preimage)))), "preimage error");
        _;
    }

    // 校验逻辑：合约Id所对应的合同是可提现的
    modifier withdrawable(bytes32 _lockId) {

        // 要求：合约尚未提现
        require(locks[_lockId].withdrawn == false, "lock is already withdraw");

        // 要求：提现的时间在锁定高度内
        require(locks[_lockId].nLockNum > block.number, "blockNum is already greater than nLockNum");
        _;
    }

    // 校验逻辑：合约Id所对应的合同是可退款的
    modifier refundable(bytes32 _lockId) {

        // 要求：合约尚未退款
        require(locks[_lockId].refunded == false, "lock is already refund");

        // 要求：合约尚未提现
        require(locks[_lockId].withdrawn == false, "lock is already withdraw");

        // 要求：当前时间已经超过合约的锁定时间
        require(locks[_lockId].nLockNum <= block.number, "blockNum is less than nLockNum");
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

    /// Get the specialFeeRate
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

    /// Changes the feeRate
    function changeFeeRate(uint feeRate_) external isAdmin {
        require(feeRate_ <= 1e18, "feeRate illegal");
        feeRate = feeRate_;
    }

    /**
     * @dev 创建一个hashlock的锁定
     *
     * @param _receiver 接收者
     * @param _hValue A sha-2 sha256 hash hValue.
     * @param _nLockNum 锁定的高度，此高度内能取现，超过此高度智能赎回
     * @return lockId Id of the new HTLC. This is needed for subsequent
     *                    calls.
     */
    function lock(address _receiver, bytes32 _hValue, uint _nLockNum)
    external
    payable
    validAmount
    validLockNum(_nLockNum)
    returns (bytes32 lockId)
    {

        // 根据 【发送者 + 接受者 + 金额 + hValue + 锁定时间】 作为合约的唯一键
        lockId = sha256(abi.encodePacked(msg.sender, _receiver, msg.value, _hValue, _nLockNum));

        //  不接受同样参数的合约
        if (haveLock(lockId))
            revert("There is no this lockId!");


        // 将构锁定同放入到mapping
        locks[lockId] = Lock(
            msg.sender,
            _receiver,
            msg.value,
            _hValue,
            _nLockNum,
            false,
            false,
            "0x0"
        );


        // 发送事件
        emit LogLock(
            lockId,
            msg.sender,
            _receiver,
            msg.value,
            _hValue,
            _nLockNum
        );
    }


    function withdraw(bytes32 _lockId, string _preimage)
    external
    lockExists(_lockId)
    lockMatches(_lockId, _preimage)
    withdrawable(_lockId)
    returns (bool)
    {
        // 提取出对应的合约
        Lock storage c = locks[_lockId];

        // 记录原相
        c.preimage = _preimage;

        // 标记合约已经提现
        c.withdrawn = true;

        // 手续费转账转账
        uint fee = feeTransfer(c.amount);

        // 向提现者转账(从当前合约的balance 转账给 c.receiver）
        c.receiver.transfer(c.amount.sub(fee));

        // 发送事件
        emit LogWithdraw(_lockId, _preimage);
        return true;
    }


    function refund(bytes32 _lockId)
    external
    lockExists(_lockId)
    refundable(_lockId)
    returns (bool)
    {
        // 提取出对应的合约
        Lock storage c = locks[_lockId];

        // 标记合约已经退款
        c.refunded = true;

        // 向合约建立者转账
        c.sender.transfer(c.amount);

        // 发送事件
        emit LogRefund(_lockId);
        return true;
    }


    function getLock(bytes32 _lockId)
    external
    view
    returns (
        address sender,
        address receiver,
        uint amount,
        bytes32 hValue,
        uint nLockNum,
        bool withdrawn,
        bool refunded,
        string preimage
    )
    {

        // 检查合约存在，否则直接返回
        if (haveLock(_lockId) == false)
            return;

        // 提取对应的合约
        Lock storage c = locks[_lockId];

        // 返回合约明细
        return (c.sender, c.receiver, c.amount, c.hValue, c.nLockNum,
        c.withdrawn, c.refunded, c.preimage);
    }


    function haveLock(bytes32 _lockId)
    internal
    view
    returns (bool exists)
    {
        // 根据合约（结构体）的sender 不为默认值作为判断合约是否存在的判断条件
        exists = (locks[_lockId].sender != address(0));
    }

    /// Transfer fee from msg.sender to feeAccount
    function feeTransfer(uint amount_) internal returns (uint){
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
        feeAccount.transfer(fee);
        return fee;
    }
}