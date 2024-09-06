// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "pancake-v4-core/src/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "pancake-v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "pancake-v4-core/src/types/BeforeSwapDelta.sol";
import {PoolId, PoolIdLibrary} from "pancake-v4-core/src/types/PoolId.sol";
import {ICLPoolManager} from "pancake-v4-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import {CLBaseHook} from "./CLBaseHook.sol";

import {LPFeeLibrary} from "pancake-v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "pancake-v4-core/src/types/Currency.sol";
import {CurrencySettlement} from "pancake-v4-core/test/helpers/CurrencySettlement.sol";

interface IVeCake {
    function balanceOf(address account) external view returns (uint256 balance);
}

/// @notice VeCakeMembershipHook provides the following features for veCake holders:
///     1. veCake holder will get 0% swap fee for the first hour
///     2. veCake holder will get 5% more tokenOut when swap exactIn token0 for token1 subsidised by hook
contract VeCakeMembershipHook is CLBaseHook {
    using CurrencySettlement for Currency;
    using PoolIdLibrary for PoolKey;

    IVeCake public veCake;
    mapping(PoolId => uint24) public poolIdToLpFee;
    uint256 public promoEndDate;

    constructor(ICLPoolManager _poolManager, address _veCake) CLBaseHook(_poolManager) {
        veCake = IVeCake(_veCake);
    }

    function getHooksRegistrationBitmap() external pure override returns (uint16) {
        return _hooksRegistrationBitmapFrom(
            Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: true,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnsDelta: false,
                afterSwapReturnsDelta: true,
                afterAddLiquidityReturnsDelta: false,
                afterRemoveLiquidityReturnsDelta: false
            })
        );
    }

    function afterInitialize(address, PoolKey calldata key, uint160, int24, bytes calldata hookData)
        external
        override
        returns (bytes4)
    {
        uint24 swapFee = abi.decode(hookData, (uint24));
        poolIdToLpFee[key.toId()] = swapFee;

        promoEndDate = block.timestamp + 1 hours;
        return this.afterInitialize.selector;
    }

    function beforeSwap(address, PoolKey calldata key, ICLPoolManager.SwapParams calldata, bytes calldata)
        external
        view
        override
        poolManagerOnly
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // return early if promo has ended
        if (block.timestamp > promoEndDate) {
            return (
                this.beforeSwap.selector,
                BeforeSwapDeltaLibrary.ZERO_DELTA,
                poolIdToLpFee[key.toId()] | LPFeeLibrary.OVERRIDE_FEE_FLAG
            );
        }

        uint24 lpFee = veCake.balanceOf(tx.origin) >= 1 ether ? 0 : poolIdToLpFee[key.toId()];
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, lpFee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        ICLPoolManager.SwapParams calldata param,
        BalanceDelta delta,
        bytes calldata
    ) external override poolManagerOnly returns (bytes4, int128) {
        // return early if promo has ended
        if (block.timestamp > promoEndDate) {
            return (this.afterSwap.selector, 0);
        }

        // param.amountSpecified < 0 implies exactIn
        if (param.zeroForOne && param.amountSpecified < 0 && veCake.balanceOf(tx.origin) >= 1 ether) {
            // delta.amount1 is positive as zeroForOne
            int128 extraToken = delta.amount1() * 5 / 100;

            // settle and return negative value to indicate that hook is giving token
            key.currency1.settle(vault, address(this), uint128(extraToken), false);
            return (this.afterSwap.selector, -extraToken);
        }

        return (this.afterSwap.selector, 0);
    }
}
