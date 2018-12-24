pragma solidity ^0.4.23;
pragma experimental "v0.5.0";

contract HashedTimelock{

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


    function getShaxx(string _x) public pure returns (bytes32){       
        return sha256(abi.encodePacked(sha256(abi.encodePacked(_x))));
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

    // 测试assert
    modifier assertTest() {
        assert(0==1);
        _;
    }

    // 校验逻辑：合约Id所对应的合同是可提现的
    modifier withdrawable(bytes32 _lockId) {

        // 要求：提现者是合约指定的接收者
        require(locks[_lockId].receiver == msg.sender, "receiver error");

        // 要求：合约尚未提现
        require(locks[_lockId].withdrawn == false, "lock is already withdraw");

        // 要求：提现的时间在锁定高度内
        require(locks[_lockId].nLockNum > block.number, "blockNum is already greater than nLockNum");
        _;
    }

    // 校验逻辑：合约Id所对应的合同是可退款的
    modifier refundable(bytes32 _lockId) {

        // 要求：发起退款的用户是合约的建立者
        require(locks[_lockId].sender == msg.sender, "sender error");

        // 要求：合约尚未退款
        require(locks[_lockId].refunded == false, "lock is already refund");

        // 要求：合约尚未提现
        require(locks[_lockId].withdrawn == false, "lock is already withdraw");

        // 要求：当前时间已经超过合约的锁定时间
        require(locks[_lockId].nLockNum <= block.number, "blockNum is less than nLockNum");
        _;
    }



    // LockContract 容器
    mapping(bytes32 => Lock) locks;

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

        // 向提现者转账(从当前合约的balance 转账给 c.receiver）
        c.receiver.transfer(c.amount);

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
    public
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

}