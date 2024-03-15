// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "@pancakeswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@pancakeswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@pancakeswap/v4-core/src/types/PoolId.sol";
import {IBinPoolManager} from "@pancakeswap/v4-core/src/pool-bin/interfaces/IBinPoolManager.sol";
import {BinBaseHook} from "./BinBaseHook.sol";

/// @notice BinCounterHook is a contract that counts the number of times a hook is called
/// @dev note the code is not production ready, it is only to share how a hook looks like
contract BinCounterHook is BinBaseHook {
    using PoolIdLibrary for PoolKey;

    mapping(PoolId => uint256 count) public beforeMintCount;
    mapping(PoolId => uint256 count) public afterMintCount;
    mapping(PoolId => uint256 count) public beforeSwapCount;
    mapping(PoolId => uint256 count) public afterSwapCount;

    constructor(IBinPoolManager _poolManager) BinBaseHook(_poolManager) {}

    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeMint: true,
                afterMint: true,
                beforeBurn: false,
                afterBurn: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                noOp: false
            })
        );
    }

    function beforeMint(address, PoolKey calldata key, IBinPoolManager.MintParams calldata, bytes calldata)
        external
        override
        poolManagerOnly
        returns (bytes4)
    {
        beforeMintCount[key.toId()]++;
        return this.beforeMint.selector;
    }

    function afterMint(address, PoolKey calldata key, IBinPoolManager.MintParams calldata, BalanceDelta, bytes calldata)
        external
        override
        poolManagerOnly
        returns (bytes4)
    {
        afterMintCount[key.toId()]++;
        return this.afterMint.selector;
    }

    function beforeSwap(address, PoolKey calldata key, bool, uint128, bytes calldata)
        external
        override
        poolManagerOnly
        returns (bytes4)
    {
        beforeSwapCount[key.toId()]++;
        return this.beforeSwap.selector;
    }

    function afterSwap(address, PoolKey calldata key, bool, uint128, BalanceDelta, bytes calldata)
        external
        override
        poolManagerOnly
        returns (bytes4)
    {
        afterSwapCount[key.toId()]++;
        return this.afterSwap.selector;
    }
}
