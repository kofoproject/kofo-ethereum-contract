pragma solidity ^0.4.0;

contract SolUtil {


    function getShaxx(bytes32 _x) public pure returns (bytes32){
        return sha256(_x);
    }

}
