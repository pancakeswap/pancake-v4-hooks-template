// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {PoolKey} from "@pancakeswap/v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@pancakeswap/v4-core/src/types/BeforeSwapDelta.sol";
import {PoolId, PoolIdLibrary} from "@pancakeswap/v4-core/src/types/PoolId.sol";
import {ICLPoolManager} from "@pancakeswap/v4-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import {CLBaseHook} from "./CLBaseHook.sol";

import {console2} from "forge-std/console2.sol";

interface IVeCake {
    function balanceOf(address account) external view returns (uint256 balance);
}

/// @notice VeCakeWhitelistHook allows only veCake holder to trade with the pool within the first hour
/// Idea: 1. A PCS partner protocol launch a new protocol by adding liquidity XX-ETH 
///       2. Only veCake holder can buy the token in the first hour and public access will be granted after.  
contract VeCakeWhitelistHook is CLBaseHook {
    using PoolIdLibrary for PoolKey;

    error PoolNotOpenForPublicTradeYet();

    IVeCake veCake;

    // The time when public trade starts, before this, only veCake holder can trade
    uint256 public publicTradeStartTime;

    constructor(ICLPoolManager _poolManager, address _veCake) CLBaseHook(_poolManager) {
        veCake = IVeCake(_veCake);
        publicTradeStartTime = block.timestamp + 1 hours;
    }

    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnsDelta: false,
                afterSwapReturnsDelta: false,
                afterAddLiquidityReturnsDelta: false,
                afterRemoveLiquidityReturnsDelta: false
            })
        );
    }

    function beforeSwap(address, PoolKey calldata key, ICLPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        poolManagerOnly
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        /// Only allow non veCake holder to trade after publicTradeStartTime
        if (block.timestamp < publicTradeStartTime && veCake.balanceOf(tx.origin) < 1 ether) {
            revert PoolNotOpenForPublicTradeYet();
        }

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }
}
