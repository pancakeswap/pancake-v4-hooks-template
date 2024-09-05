// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {BinPoolManager} from "pancake-v4-core/src/pool-bin/BinPoolManager.sol";
import {Vault} from "pancake-v4-core/src/Vault.sol";
import {Currency} from "pancake-v4-core/src/types/Currency.sol";
import {SortTokens} from "pancake-v4-core/test/helpers/SortTokens.sol";
import {PoolKey} from "pancake-v4-core/src/types/PoolKey.sol";
import {SafeCast} from "pancake-v4-core/src/pool-bin/libraries/math/SafeCast.sol";
import {BinPositionManager} from "pancake-v4-periphery/src/pool-bin/BinPositionManager.sol";
import {IBinPositionManager} from "pancake-v4-periphery/src/pool-bin/interfaces/IBinPositionManager.sol";
import {IBinRouterBase} from "pancake-v4-periphery/src/pool-bin/interfaces/IBinRouterBase.sol";
import {Planner, Plan} from "pancake-v4-periphery/src/libraries/Planner.sol";
import {Actions} from "pancake-v4-periphery/src/libraries/Actions.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {UniversalRouter, RouterParameters} from "pancake-v4-universal-router/src/UniversalRouter.sol";
import {Commands} from "pancake-v4-universal-router/src/libraries/Commands.sol";
import {ActionConstants} from "pancake-v4-periphery/src/libraries/ActionConstants.sol";

contract BinTestUtils is DeployPermit2 {
    using SafeCast for uint256;
    using Planner for Plan;

    Vault vault;
    BinPoolManager poolManager;
    BinPositionManager positionManager;
    IAllowanceTransfer permit2;
    UniversalRouter universalRouter;

    function deployContractsWithTokens() internal returns (Currency, Currency) {
        vault = new Vault();
        poolManager = new BinPoolManager(vault, 500000);
        vault.registerApp(address(poolManager));

        permit2 = IAllowanceTransfer(deployPermit2());
        positionManager = new BinPositionManager(vault, poolManager, permit2);

        RouterParameters memory params = RouterParameters({
            permit2: address(permit2),
            weth9: address(0),
            v2Factory: address(0),
            v3Factory: address(0),
            v3Deployer: address(0),
            v2InitCodeHash: bytes32(0),
            v3InitCodeHash: bytes32(0),
            stableFactory: address(0),
            stableInfo: address(0),
            v4Vault: address(vault),
            v4ClPoolManager: address(0),
            v4BinPoolManager: address(poolManager),
            v3NFTPositionManager: address(0),
            v4ClPositionManager: address(0),
            v4BinPositionManager: address(positionManager)
        });
        universalRouter = new UniversalRouter(params);

        MockERC20 token0 = new MockERC20("token0", "T0", 18);
        MockERC20 token1 = new MockERC20("token1", "T1", 18);

        // approve permit2 contract to transfer our funds
        token0.approve(address(permit2), type(uint256).max);
        token1.approve(address(permit2), type(uint256).max);

        permit2.approve(address(token0), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(token1), address(positionManager), type(uint160).max, type(uint48).max);

        permit2.approve(address(token0), address(universalRouter), type(uint160).max, type(uint48).max);
        permit2.approve(address(token1), address(universalRouter), type(uint160).max, type(uint48).max);

        return SortTokens.sort(token0, token1);
    }

    /// @notice add liqudiity to pool key,
    function addLiquidity(
        PoolKey memory key,
        uint128 amountX,
        uint128 amountY,
        uint24 currentActiveId,
        uint24 numOfBins,
        address recipient
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

        IBinPositionManager.BinAddLiquidityParams memory params = IBinPositionManager.BinAddLiquidityParams({
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
            to: recipient
        });

        Plan memory planner = Planner.init().add(Actions.BIN_ADD_LIQUIDITY, abi.encode(params));
        bytes memory data = planner.finalizeModifyLiquidityWithClose(params.poolKey);
        positionManager.modifyLiquidities(data, block.timestamp);
    }

    function exactInputSingle(IBinRouterBase.BinSwapExactInputSingleParams memory params) internal {
        Plan memory plan = Planner.init().add(Actions.BIN_SWAP_EXACT_IN_SINGLE, abi.encode(params));
        bytes memory data = params.swapForY
            ? plan.finalizeSwap(params.poolKey.currency0, params.poolKey.currency1, ActionConstants.MSG_SENDER)
            : plan.finalizeSwap(params.poolKey.currency1, params.poolKey.currency0, ActionConstants.MSG_SENDER);

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V4_SWAP)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = data;

        universalRouter.execute(commands, inputs);
    }

    function exactOutputSingle(IBinRouterBase.BinSwapExactOutputSingleParams memory params) internal {
        Plan memory plan = Planner.init().add(Actions.BIN_SWAP_EXACT_OUT_SINGLE, abi.encode(params));
        bytes memory data = params.swapForY
            ? plan.finalizeSwap(params.poolKey.currency0, params.poolKey.currency1, ActionConstants.MSG_SENDER)
            : plan.finalizeSwap(params.poolKey.currency1, params.poolKey.currency0, ActionConstants.MSG_SENDER);

        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V4_SWAP)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = data;

        universalRouter.execute(commands, inputs);
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

    /// @notice permit2 approve from user addr to contractToApprove for currency
    function permit2Approve(address userAddr, Currency currency, address contractToApprove) internal {
        vm.startPrank(userAddr);

        // If contractToApprove uses permit2, we must execute 2 permits/approvals.
        // 1. First, the caller must approve permit2 on the token.
        IERC20(Currency.unwrap(currency)).approve(address(permit2), type(uint256).max);

        // 2. Then, the caller must approve contractToApprove as a spender of permit2.
        permit2.approve(Currency.unwrap(currency), address(contractToApprove), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }
}
