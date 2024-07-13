// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {PoolKey} from "@pancakeswap/v4-core/src/types/PoolKey.sol";
import {LPFeeLibrary} from "@pancakeswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@pancakeswap/v4-core/src/types/BeforeSwapDelta.sol";
import {PoolId, PoolIdLibrary} from "@pancakeswap/v4-core/src/types/PoolId.sol";
import {ICLPoolManager} from "@pancakeswap/v4-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import {CLBaseHook} from "./CLBaseHook.sol";

interface IVeCake {
    function balanceOf(address account) external view returns (uint256 balance);
}

/// @notice VeCakeSwapDiscountHook provides 50% swap fee discount for veCake holder
/// Idea:
///   1. PancakeSwap has veCake (vote-escrowed Cake), user obtain veCake by locking cake
///   2. If the swapper holds veCake, provide 50% swap fee discount
/// Implementation:
///   1. When pool is initialized, at `afterInitialize` we store what is the intended swap fee for the pool
//    2. During `beforeSwap` callback, the hook checks if users is veCake holder and provide discount accordingly
contract VeCakeSwapDiscountHook is CLBaseHook {
    using PoolIdLibrary for PoolKey;
    using LPFeeLibrary for uint24;

    IVeCake public veCake;
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

    /// @notice The hook called after the state of a pool is initialized
    /// @return bytes4 The function selector for the hook
    function afterInitialize(address, PoolKey calldata key, uint160, int24, bytes calldata hookData)
        external
        override
        poolManagerOnly
        returns (bytes4)
    {
        // Get the intended lpFee for this pool and store in mapping
        uint24 lpFee = abi.decode(hookData, (uint24));
        poolIdToLpFee[key.toId()] = lpFee;

        return this.afterInitialize.selector;
    }

    /// @notice The hook called before a swap
    /// @return bytes4 The function selector for the hook
    /// @return BeforeSwapDelta The hook's delta in specified and unspecified currencies.
    /// @return uint24 Optionally override the lp fee, only used if three conditions are met:
    ///     1) the Pool has a dynamic fee,
    ///     2) the value's override flag is set to 1 i.e. vaule & OVERRIDE_FEE_FLAG = 0x400000 != 0
    ///     3) the value is less than or equal to the maximum fee (1 million)
    function beforeSwap(address, PoolKey calldata key, ICLPoolManager.SwapParams calldata, bytes calldata)
        external
        override
        poolManagerOnly
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        uint24 lpFee = poolIdToLpFee[key.toId()];

        /// If veCake holder, lpFee is half
        if (veCake.balanceOf(tx.origin) >= 1 ether) {
            lpFee = poolIdToLpFee[key.toId()] / 2;
        }

        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, lpFee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }
}