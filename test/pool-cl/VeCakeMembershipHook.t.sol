// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {Test} from "forge-std/Test.sol";
import {Constants} from "pancake-v4-core/test/pool-cl/helpers/Constants.sol";
import {Currency} from "pancake-v4-core/src/types/Currency.sol";
import {PoolKey} from "pancake-v4-core/src/types/PoolKey.sol";
import {CLPoolParametersHelper} from "pancake-v4-core/src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {CLTestUtils} from "./utils/CLTestUtils.sol";
import {CLPoolParametersHelper} from "pancake-v4-core/src/pool-cl/libraries/CLPoolParametersHelper.sol";
import {PoolIdLibrary} from "pancake-v4-core/src/types/PoolId.sol";
import {ICLRouterBase} from "pancake-v4-periphery/src/pool-cl/interfaces/ICLRouterBase.sol";

import {VeCakeMembershipHook} from "../../src/pool-cl/VeCakeMembershipHook.sol";
import {LPFeeLibrary} from "pancake-v4-core/src/libraries/LPFeeLibrary.sol";

contract VeCakeMembershipHookTest is Test, CLTestUtils {
    using PoolIdLibrary for PoolKey;
    using CLPoolParametersHelper for bytes32;

    VeCakeMembershipHook hook;
    Currency currency0;
    Currency currency1;
    PoolKey key;
    MockERC20 veCake = new MockERC20("veCake", "veCake", 18);
    address alice = makeAddr("alice");

    function setUp() public {
        (currency0, currency1) = deployContractsWithTokens();
        hook = new VeCakeMembershipHook(poolManager, address(veCake));

        // create the pool key
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            hooks: hook,
            poolManager: poolManager,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            parameters: bytes32(uint256(hook.getHooksRegistrationBitmap())).setTickSpacing(10)
        });

        // initialize pool at 1:1 price point and set 3000 as initial lp fee, lpFee is stored in the hook
        poolManager.initialize(key, Constants.SQRT_RATIO_1_1, abi.encode(uint24(3000)));

        // add liquidity so that swap can happen
        MockERC20(Currency.unwrap(currency0)).mint(address(this), 100 ether);
        MockERC20(Currency.unwrap(currency1)).mint(address(this), 100 ether);
        addLiquidity(key, 100 ether, 100 ether, -60, 60, address(this));

        // approve from alice for swap in the test cases below
        permit2Approve(alice, currency0, address(universalRouter));
        permit2Approve(alice, currency1, address(universalRouter));

        // mint alice token for trade later
        MockERC20(Currency.unwrap(currency0)).mint(address(alice), 100 ether);

        // mint currency 1 for hook to give out
        MockERC20(Currency.unwrap(currency1)).mint(address(hook), 100 ether);
    }

    function testNonVeCakeHolder() public {
        uint256 amtOut = _swap();

        // amt out be at least 0.3% lesser due to swap fee
        assertLe(amtOut, 0.997 ether);
    }

    function testVeCakeHolder_AfterPromoPeriod() public {
        vm.warp(hook.promoEndDate() + 1);

        // mint alice veCake
        veCake.mint(address(alice), 1 ether);

        uint256 amtOut = _swap();

        // amt out be at least 0.3% lesser due to swap fee
        assertLe(amtOut, 0.997 ether);
    }

    function testVeCakeHolder() public {
        // mint alice veCake
        veCake.mint(address(alice), 1 ether);

        uint256 amtOut = _swap();

        // amount out is almost 1.05 due to the 5% subsidy from hook and 0% swap fee
        assertGt(amtOut, 1.04 ether);
    }

    function _swap() internal returns (uint256 amtOut) {
        uint256 amt1BalBefore = MockERC20(Currency.unwrap(currency1)).balanceOf(address(alice));

        // set alice as tx.origin
        vm.prank(address(alice), address(alice));
        exactInputSingle(
            ICLRouterBase.CLSwapExactInputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountIn: 1 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0,
                hookData: new bytes(0)
            })
        );

        uint256 amt1BalAfter = MockERC20(Currency.unwrap(currency1)).balanceOf(address(alice));
        amtOut = amt1BalAfter - amt1BalBefore;
    }
}
