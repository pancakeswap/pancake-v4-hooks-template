// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Test} from "forge-std/Test.sol";
import {Currency} from "pancake-v4-core/src/types/Currency.sol";
import {PoolKey} from "pancake-v4-core/src/types/PoolKey.sol";
import {BinPoolParametersHelper} from "pancake-v4-core/src/pool-bin/libraries/BinPoolParametersHelper.sol";
import {BinCounterHook} from "../../src/pool-bin/BinCounterHook.sol";
import {BinTestUtils} from "./utils/BinTestUtils.sol";
import {PoolIdLibrary} from "pancake-v4-core/src/types/PoolId.sol";
import {IBinRouterBase} from "pancake-v4-periphery/src/pool-bin/interfaces/IBinRouterBase.sol";

contract BinCounterHookTest is Test, BinTestUtils {
    using PoolIdLibrary for PoolKey;
    using BinPoolParametersHelper for bytes32;

    BinCounterHook counterHook;
    Currency currency0;
    Currency currency1;
    PoolKey key;
    uint24 ACTIVE_ID = 2 ** 23;

    function setUp() public {
        (currency0, currency1) = deployContractsWithTokens();
        counterHook = new BinCounterHook(poolManager);

        // create the pool key
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: counterHook,
            poolManager: poolManager,
            fee: uint24(3000),
            // binstep: 10 = 0.1% price jump per bin
            parameters: bytes32(uint256(counterHook.getHooksRegistrationBitmap())).setBinStep(10)
        });

        // initialize pool at 1:1 price point (assume stablecoin pair)
        poolManager.initialize(key, ACTIVE_ID, new bytes(0));
    }

    function testLiquidityCallback() public {
        assertEq(counterHook.beforeMintCount(key.toId()), 0);
        assertEq(counterHook.afterMintCount(key.toId()), 0);

        MockERC20(Currency.unwrap(currency0)).mint(address(this), 1 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 1 ether);
        addLiquidity(key, 1 ether, 1 ether, ACTIVE_ID, 3, address(this));

        assertEq(counterHook.beforeMintCount(key.toId()), 1);
        assertEq(counterHook.afterMintCount(key.toId()), 1);
    }

    function testSwapCallback() public {
        MockERC20(Currency.unwrap(currency0)).mint(address(this), 1 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 1 ether);
        addLiquidity(key, 1 ether, 1 ether, ACTIVE_ID, 3, address(this));

        assertEq(counterHook.beforeSwapCount(key.toId()), 0);
        assertEq(counterHook.afterSwapCount(key.toId()), 0);

        MockERC20(Currency.unwrap(currency0)).mint(address(this), 0.1 ether);
        exactInputSingle(
            IBinRouterBase.BinSwapExactInputSingleParams({
                poolKey: key,
                swapForY: true,
                amountIn: 0.1 ether,
                amountOutMinimum: 0,
                hookData: new bytes(0)
            })
        );

        assertEq(counterHook.beforeSwapCount(key.toId()), 1);
        assertEq(counterHook.afterSwapCount(key.toId()), 1);
    }
}
