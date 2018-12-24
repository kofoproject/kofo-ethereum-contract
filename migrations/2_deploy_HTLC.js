var MintableToken = artifacts.require("./MintableToken.sol");
var HashedTimelock = artifacts.require("./HashedTimelock.sol");
var HashedTimelockERC20 = artifacts.require("./HashedTimelockERC20.sol");
var SolUtil = artifacts.require("./SolUtil.sol");

module.exports = function (deployer) {

    deployer.deploy(HashedTimelockERC20);
    deployer.deploy(MintableToken);
    deployer.deploy(HashedTimelock);
    deployer.deploy(SolUtil);


};