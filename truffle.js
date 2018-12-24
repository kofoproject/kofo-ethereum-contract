require('babel-register');
require('babel-polyfill');

var HDWalletProvider = require("truffle-hdwallet-provider");
var mnemonic = "crack caught sleep eagle tissue audit sure engine unveil deposit diet call";


module.exports = {

    networks: {
        development: {
            host: "localhost",
            port: 8545,
            network_id: "*" // 匹配任何network id
        },
        // the ropsten testnet config.
        ropsten: {
            provider: function () {
                return new HDWalletProvider(mnemonic,
                    "https://ropsten.infura.io/J9FLxoqo8YIuwYJRU9OI")
            },
            network_id: "3"
        }
    }
};
