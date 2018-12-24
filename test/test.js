// import sha256
import {
    sha256, sha224
} from './jslib/sha256.min'


// import contract.sol
const HashedTimelock = artifacts.require('./HashedTimelock.sol');
const SolUtil = artifacts.require('./SolUtil.sol');


// values and functions
const REQUIRE_FAILED_MSG = 'VM Exception while processing transaction: revert';

const hourSeconds = 3600;

const log = function () {
    console.log(arguments);
};


// test logics
contract('HashedTimelock', accounts => {
    const sender = accounts[1];
    const receiver = accounts[2];

    it('newContract() should create new contract and store correct details', async () => {


        const htlc = await HashedTimelock.deployed();
        const utl = await SolUtil.deployed();

        let hash = await utl.getShaxx(123);
        log(1);
        log(hash);


        log(2);

        let hashByContract = await htlc.getShaxx(123);
        log(hashByContract);

        log(3)
    })
});
