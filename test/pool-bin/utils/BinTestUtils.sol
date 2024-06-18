// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Test} from "forge-std/Test.sol";
import {BinPoolManager} from "@pancakeswap/v4-core/src/pool-bin/BinPoolManager.sol";
import {Vault} from "@pancakeswap/v4-core/src/Vault.sol";
import {Currency} from "@pancakeswap/v4-core/src/types/Currency.sol";
import {SortTokens} from "@pancakeswap/v4-core/test/helpers/SortTokens.sol";
import {PoolKey} from "@pancakeswap/v4-core/src/types/PoolKey.sol";
import {SafeCast} from "@pancakeswap/v4-core/src/pool-bin/libraries/math/SafeCast.sol";
import {BinSwapRouter} from "@pancakeswap/v4-periphery/src/pool-bin/BinSwapRouter.sol";
import {BinFungiblePositionManager} from "@pancakeswap/v4-periphery/src/pool-bin/BinFungiblePositionManager.sol";
import {IBinFungiblePositionManager} from
    "@pancakeswap/v4-periphery/src/pool-bin/interfaces/IBinFungiblePositionManager.sol";

contract BinTestUtils {
    using SafeCast for uint256;

    Vault vault;
    BinPoolManager poolManager;
    BinFungiblePositionManager positionManager;
    BinSwapRouter swapRouter;

    function deployContractsWithTokens() internal returns (Currency, Currency) {
        vault = new Vault();
        poolManager = new BinPoolManager(vault, 500000);
        vault.registerApp(address(poolManager));

        positionManager = new BinFungiblePositionManager(vault, poolManager, address(0));
        swapRouter = new BinSwapRouter(vault, poolManager, address(0));

        MockERC20 token0 = new MockERC20("token0", "T0", 18);
        MockERC20 token1 = new MockERC20("token1", "T1", 18);

        address[2] memory approvalAddress = [address(positionManager), address(swapRouter)];
        for (uint256 i; i < approvalAddress.length; i++) {
            token0.approve(approvalAddress[i], type(uint256).max);
            token1.approve(approvalAddress[i], type(uint256).max);
        }

        return SortTokens.sort(token0, token1);
    }

    /// @notice add liqudiity to pool key,
    function addLiquidity(
        PoolKey memory key,
        uint128 amountX,
        uint128 amountY,
        uint24 currentActiveId,
        uint24 numOfBins
    ) internal {
        uint24[] memory binIds = new uint24[](numOfBins);
        uint24 startId = currentActiveId - (numOfBins / 2);
        for (uint256 i; i < numOfBins; i++) {
            binIds[i] = startId;
            startId++;
        }

        uint8 nbBinX; // num of bins to the right
        uint8 nbBinY; // num of bins to the left
        for (uint256 i; i < numOfBins; ++i) {
            if (binIds[i] >= currentActiveId) nbBinX++;
            if (binIds[i] <= currentActiveId) nbBinY++;
        }

        // Equal distribution across all binds
        uint256[] memory distribX = new uint256[](numOfBins);
        uint256[] memory distribY = new uint256[](numOfBins);
        for (uint256 i; i < numOfBins; ++i) {
            uint24 binId = binIds[i];
            distribX[i] = binId >= currentActiveId && nbBinX > 0 ? uint256(1e18 / nbBinX).safe64() : 0;
            distribY[i] = binId <= currentActiveId && nbBinY > 0 ? uint256(1e18 / nbBinY).safe64() : 0;
        }

        IBinFungiblePositionManager.AddLiquidityParams memory params = IBinFungiblePositionManager.AddLiquidityParams({
            poolKey: key,
            amount0: amountX,
            amount1: amountY,
            amount0Min: 0, // note in real world, this should not be 0
            amount1Min: 0, // note in real world, this should not be 0
            activeIdDesired: uint256(currentActiveId),
            idSlippage: 0,
            deltaIds: convertToRelative(binIds, currentActiveId),
            distributionX: distribX,
            distributionY: distribY,
            to: address(this),
            deadline: block.timestamp + 600
        });

        positionManager.addLiquidity(params);
    }

    /// @dev Given list of binIds and activeIds, return the delta ids.
    //       eg. given id: [100, 101, 102] and activeId: 101, return [-1, 0, 1]
    function convertToRelative(uint24[] memory absoluteIds, uint24 activeId)
        internal
        pure
        returns (int256[] memory relativeIds)
    {
        relativeIds = new int256[](absoluteIds.length);
        for (uint256 i = 0; i < absoluteIds.length; i++) {
            relativeIds[i] = int256(uint256(absoluteIds[i])) - int256(uint256(activeId));
        }
    }
}
