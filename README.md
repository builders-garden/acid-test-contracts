## Foundry


**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ OWNER_ADDRESS=<OWNER_ADDRESS> RECEIVER_ADDRESS=<RECEIVER_ADDRESS> \ 
forge script script/AcidTestDeployer.sol:AcidTestDeployer \
--fork-url https://mainnet.base.org \
--private-key <PRIVATE_KEY> --broadcast
```

### Verify 
```shell 
forge verify-contract <CONTRACT_ADDRESS> src/AcidTest.sol:AcidTest --chain base --etherscan-api-key <BASESCAN_APIKEY> --compiler-version <COMPILER_VERSION> --constructor-args $(cast abi-encode "constructor(address,address,address,address,address)" <USDC_ADDRESS> <WETH_ADDRESS> <OWNER_ADDRESS> <AGGREGATOR_v3_ADDRESS> <RECEIVER_ADDRESS> )
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
