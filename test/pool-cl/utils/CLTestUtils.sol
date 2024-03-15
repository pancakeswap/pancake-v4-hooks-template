// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Test, console} from "forge-std/Test.sol";
import {CLPoolManager} from "@pancakeswap/v4-core/src/pool-cl/CLPoolManager.sol";
import {Vault} from "@pancakeswap/v4-core/src/Vault.sol";
import {Currency} from "@pancakeswap/v4-core/src/types/Currency.sol";
import {SortTokens} from "@pancakeswap/v4-core/test/helpers/SortTokens.sol";
import {PoolKey} from "@pancakeswap/v4-core/src/types/PoolKey.sol";
import {CLSwapRouter} from "@pancakeswap/v4-periphery/src/pool-cl/CLSwapRouter.sol";
import {NonfungiblePositionManager} from "@pancakeswap/v4-periphery/src/pool-cl/NonfungiblePositionManager.sol";
import {INonfungiblePositionManager} from
    "@pancakeswap/v4-periphery/src/pool-cl/interfaces/INonfungiblePositionManager.sol";

contract CLTestUtils {
    Vault vault;
    CLPoolManager poolManager;
    NonfungiblePositionManager nfp;
    CLSwapRouter swapRouter;

    function deployContractsWithTokens() internal returns (Currency, Currency) {
        vault = new Vault();
        poolManager = new CLPoolManager(vault, 500000);
        vault.registerPoolManager(address(poolManager));

        nfp = new NonfungiblePositionManager(vault, poolManager, address(0), address(0));
        swapRouter = new CLSwapRouter(vault, poolManager, address(0));

        MockERC20 token0 = new MockERC20("token0", "T0", 18);
        MockERC20 token1 = new MockERC20("token1", "T1", 18);

        address[2] memory approvalAddress = [address(nfp), address(swapRouter)];
        for (uint256 i; i < approvalAddress.length; i++) {
            token0.approve(approvalAddress[i], type(uint256).max);
            token1.approve(approvalAddress[i], type(uint256).max);
        }

        return SortTokens.sort(token0, token1);
    }

    function addLiquidity(PoolKey memory key, uint256 amount0, uint256 amount1, int24 tickLower, int24 tickUpper)
        internal
    {
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            poolKey: key,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        nfp.mint(mintParams);
    }
}
