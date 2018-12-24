# ref

- https://github.com/chatch/hashed-timelock-contract-ethereum
- https://github.com/OpenZeppelin/openzeppelin-solidity

# 合约文件
必要文件
- 跨链需要的contract 是 /contracts 目录下，HashedTimelock 和 HashedTimelockERC20两个合约，其他都是帮助性质的合约（帮助验证ERC20）
- 项目使用了truffle，但是不必须依赖truffle ，contract 可以单独使用，项目中主要是使用truffle 的脚手架能力和test


# 测试用例

测试用例使用了truffle test，通过如下脚本运行（需要安装truffle,mocha）
```bash

cd ${PROJECT_DIR}

truffle develop

migrate --reset

test


```


# 安装 truffle,mocha

npm 安装truffle
```bash

npm install -g truffle
npm install -g mocha

```