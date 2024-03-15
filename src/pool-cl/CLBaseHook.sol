// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    HOOKS_BEFORE_INITIALIZE_OFFSET,
    HOOKS_AFTER_INITIALIZE_OFFSET,
    HOOKS_BEFORE_ADD_LIQUIDITY_OFFSET,
    HOOKS_AFTER_ADD_LIQUIDITY_OFFSET,
    HOOKS_BEFORE_REMOVE_LIQUIDITY_OFFSET,
    HOOKS_AFTER_REMOVE_LIQUIDITY_OFFSET,
    HOOKS_BEFORE_SWAP_OFFSET,
    HOOKS_AFTER_SWAP_OFFSET,
    HOOKS_BEFORE_DONATE_OFFSET,
    HOOKS_AFTER_DONATE_OFFSET,
    HOOKS_NO_OP_OFFSET
} from "@pancakeswap/v4-core/src/pool-cl/interfaces/ICLHooks.sol";
import {PoolKey} from "@pancakeswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@pancakeswap/v4-core/src/types/BalanceDelta.sol";
import {IHooks} from "@pancakeswap/v4-core/src/interfaces/IHooks.sol";
import {IVault} from "@pancakeswap/v4-core/src/interfaces/IVault.sol";
import {ICLHooks} from "@pancakeswap/v4-core/src/pool-cl/interfaces/ICLHooks.sol";
import {ICLPoolManager} from "@pancakeswap/v4-core/src/pool-cl/interfaces/ICLPoolManager.sol";
import {CLPoolManager} from "@pancakeswap/v4-core/src/pool-cl/CLPoolManager.sol";

abstract contract CLBaseHook is ICLHooks {
    error NotPoolManager();
    error NotVault();
    error NotSelf();
    error InvalidPool();
    error LockFailure();
    error HookNotImplemented();

    struct Permissions {
        bool beforeInitialize;
        bool afterInitialize;
        bool beforeAddLiquidity;
        bool afterAddLiquidity;
        bool beforeRemoveLiquidity;
        bool afterRemoveLiquidity;
        bool beforeSwap;
        bool afterSwap;
        bool beforeDonate;
        bool afterDonate;
        bool noOp;
    }

    /// @notice The address of the pool manager
    ICLPoolManager public immutable poolManager;

    /// @notice The address of the vault
    IVault public immutable vault;

    constructor(ICLPoolManager _poolManager) {
        poolManager = _poolManager;
        vault = CLPoolManager(address(poolManager)).vault();
    }

    /// @dev Only the pool manager may call this function
    modifier poolManagerOnly() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    /// @dev Only the vault may call this function
    modifier vaultOnly() {
        if (msg.sender != address(vault)) revert NotVault();
        _;
    }

    /// @dev Only this address may call this function
    modifier selfOnly() {
        if (msg.sender != address(this)) revert NotSelf();
        _;
    }

    /// @dev Only pools with hooks set to this contract may call this function
    modifier onlyValidPools(IHooks hooks) {
        if (address(hooks) != address(this)) revert InvalidPool();
        _;
    }

    /// @dev Helper function when the hook needs to get a lock from the vault. See
    ///      https://github.com/pancakeswap/pancake-v4-hooks oh hooks which perform vault.lock()
    function lockAcquired(bytes calldata data) external virtual vaultOnly returns (bytes memory) {
        (bool success, bytes memory returnData) = address(this).call(data);
        if (success) return returnData;
        if (returnData.length == 0) revert LockFailure();
        // if the call failed, bubble up the reason
        /// @solidity memory-safe-assembly
        assembly {
            revert(add(returnData, 32), mload(returnData))
        }
    }

    function beforeInitialize(address, PoolKey calldata, uint160, bytes calldata) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        ICLPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ICLPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        bytes calldata
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        ICLPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ICLPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta,
        bytes calldata
    ) external virtual returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeSwap(address, PoolKey calldata, ICLPoolManager.SwapParams calldata, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterSwap(address, PoolKey calldata, ICLPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        virtual
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function _hooksRegistrationBitmapFrom(Permissions memory permissions) internal pure returns (uint16) {
        return uint16(
            (permissions.beforeInitialize ? 1 << HOOKS_BEFORE_INITIALIZE_OFFSET : 0)
                | (permissions.afterInitialize ? 1 << HOOKS_AFTER_INITIALIZE_OFFSET : 0)
                | (permissions.beforeAddLiquidity ? 1 << HOOKS_BEFORE_ADD_LIQUIDITY_OFFSET : 0)
                | (permissions.afterAddLiquidity ? 1 << HOOKS_AFTER_ADD_LIQUIDITY_OFFSET : 0)
                | (permissions.beforeRemoveLiquidity ? 1 << HOOKS_BEFORE_REMOVE_LIQUIDITY_OFFSET : 0)
                | (permissions.afterRemoveLiquidity ? 1 << HOOKS_AFTER_REMOVE_LIQUIDITY_OFFSET : 0)
                | (permissions.beforeSwap ? 1 << HOOKS_BEFORE_SWAP_OFFSET : 0)
                | (permissions.afterSwap ? 1 << HOOKS_AFTER_SWAP_OFFSET : 0)
                | (permissions.beforeDonate ? 1 << HOOKS_BEFORE_DONATE_OFFSET : 0)
                | (permissions.afterDonate ? 1 << HOOKS_AFTER_DONATE_OFFSET : 0)
                | (permissions.noOp ? 1 << HOOKS_NO_OP_OFFSET : 0)
        );
    }
}
