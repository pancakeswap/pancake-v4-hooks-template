// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {PoolKey} from "@pancakeswap/v4-core/src/types/PoolKey.sol";
import {LPFeeLibrary} from "@pancakeswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {BalanceDelta} from "@pancakeswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@pancakeswap/v4-core/src/types/BeforeSwapDelta.sol";
import {PoolId, PoolIdLibrary} from "@pancakeswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@pancakeswap/v4-core/src/types/Currency.sol";
import {CurrencySettlement} from "@pancakeswap/v4-core/test/helpers/CurrencySettlement.sol";
import {ICLPoolManager} from "@pancakeswap/v4-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import {CLBaseHook} from "./CLBaseHook.sol";

interface IVeCake {
    function balanceOf(address account) external view returns (uint256 balance);
}

/// @notice VeCakeMembershipHook provides the following features for veCake holders:
///     1. veCake holder will get 5% more tokenOut subsidised by hook
///     2. veCake holder get 100% off swap fee for the first hour
contract VeCakeMembershipHook is CLBaseHook {
    using CurrencySettlement for Currency;
    using PoolIdLibrary for PoolKey;
    using LPFeeLibrary for uint24;

    IVeCake public veCake;
    uint256 public promoEndDate;
    mapping(PoolId => uint24) public poolIdToLpFee;

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

    /// @dev Get the intended lpFee for this pool and store in mapping
    function afterInitialize(address, PoolKey calldata key, uint160, int24, bytes calldata hookData)
        external
        override
        returns (bytes4)
    {
        (uint24 lpFee) = abi.decode(hookData, (uint24));
        poolIdToLpFee[key.toId()] = lpFee;

        promoEndDate = block.timestamp + 1 hours;
        return this.afterInitialize.selector;
    }

    function beforeSwap(address, PoolKey calldata key, ICLPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        poolManagerOnly
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        /// If within promo endDate and veCake holder, lpFee is 0
        uint24 lpFee =
            block.timestamp < promoEndDate && veCake.balanceOf(tx.origin) >= 1 ether ? 0 : poolIdToLpFee[key.toId()];

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, lpFee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    function afterSwap(
        address,
        PoolKey calldata poolKey,
        ICLPoolManager.SwapParams calldata param,
        BalanceDelta delta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        // return early if promo has ended
        if (block.timestamp > promoEndDate) {
            return (this.afterSwap.selector, 0);
        }

        /// @dev this is POC code, do not use for production, this is only for POC.
        /// Assumption: currency1 is subsidised currency and if veCake user swap token0 for token1, give 5% more token1.
        /// zeroForOne: swap token0 for token1
        /// amountSpecified < 0: indicate exactIn token0 for token1. so unspecified token is token1
        /// veCake.balanceOf(tx.origin) >= 1 ether: only veCake holder
        if (param.zeroForOne && param.amountSpecified < 0 && veCake.balanceOf(tx.origin) >= 1 ether) {
            // delta.amount1 is positive as zeroForOne
            int128 extraToken = delta.amount1() * 5 / 100;

            // settle and return negative value to indicate that hook is giving token
            poolKey.currency1.settle(vault, address(this), uint128(extraToken), false);
            return (this.afterSwap.selector, -extraToken);
        }

        return (this.afterSwap.selector, 0);
    }
}
