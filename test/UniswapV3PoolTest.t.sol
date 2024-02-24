// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {Test, console2} from "forge-std/Test.sol";

import {ERC20Mintable} from "./ERC20Mintable.sol";
import {UniswapV3Pool} from "src/UniswapV3Pool.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {TestUtils} from "test/TestUtils.sol";
contract UniswapV3PoolTest is Test, TestUtils {
    ERC20Mintable token0;
    ERC20Mintable token1;
    UniswapV3Pool pool;

    bool transferInMintCallback = true;
    bool transferInSwapCallback = true;

    struct TestCaseParams {
        uint256 wethBalance;
        uint256 usdcBalance;
        int24 currentTick;
        int24 lowerTick;
        int24 upperTick;
        uint128 liquidity;
        uint160 currentSqrtP;
        bool transferInMintCallback;
        bool transferInSwapCallback;
        bool mintLiquidity;
    }

    function setUp() public {
        token0 = new ERC20Mintable("Ether", "ETH", 18);
        token1 = new ERC20Mintable("USDC", "USDC", 18);
    }

    function testMintSuccess() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 1 ether,
            usdcBalance: 5000 ether,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInMintCallback: true,
            transferInSwapCallback: true,
            mintLiquidity: true
        });

        (uint256 poolBalance0, uint256 poolBalance1) = setupTestCase(params);
        console2.log("Pool Balance 0: ", poolBalance0);
        console2.log("Pool Balance 1: ", poolBalance1);

        uint256 expectedAmount0 = 0.99897661834742528 ether;
        uint256 expectedAmount1 = 5000 ether;

        assertEq(poolBalance0, expectedAmount0, "incorrect amount0");
        assertEq(poolBalance1, expectedAmount1, "incorrect amount1");

        assertEq(token0.balanceOf(address(pool)), expectedAmount0, "incorrect token0 balance");
        assertEq(token1.balanceOf(address(pool)), expectedAmount1, "incorrect token1 balance");

        bytes32 positionKey = keccak256(abi.encodePacked(address(this), params.lowerTick, params.upperTick));
        console2.logBytes32(positionKey);
        uint128 posLiquidity = pool.positions(positionKey);
        assertEq(posLiquidity, params.liquidity, "incorrect position liquidity");

        (bool tickInitialized, uint128 tickLiquidity) = pool.ticks(params.lowerTick);

        assertTrue(tickInitialized, "tick not initialized");
        assertEq(tickLiquidity, params.liquidity, "incorrect tick liquidity");

        (uint160 sqrtPriceX96, int24 tick) = pool.slot0();
        assertEq(sqrtPriceX96, 5602277097478614198912276234240, "incorrect sqrtPriceX96");
        assertEq(tick, 85176, "incorrect tick");
        assertEq(pool.liquidity(), 1517882343751509868544, "incorrect pool liquidity");
    }

    function testMintInvalidTickRangeLower() public {
        pool = new UniswapV3Pool(address(token0), address(token1), uint160(1), 0);
        vm.expectRevert();
        pool.mint(address(this), -887273, 0, 0, "");
    }

    function testMintZeroLiquidity() public {
        pool = new UniswapV3Pool(address(token0), address(token1), uint160(1), 0);
        vm.expectRevert();
        pool.mint(address(this), 0, 1, 0, "");
    }

    function testMintInsuffcientTokenBalance() public {
        TestCaseParams memory params = TestCaseParams({
            wethBalance: 0,
            usdcBalance: 0,
            currentTick: 85176,
            lowerTick: 84222,
            upperTick: 86129,
            liquidity: 1517882343751509868544,
            currentSqrtP: 5602277097478614198912276234240,
            transferInMintCallback: false,
            transferInSwapCallback: true,
            mintLiquidity: false
        });
        setupTestCase(params);

        vm.expectRevert(encodeError("InsufficientInputAmount()"));
        pool.mint(
            address(this),
            params.lowerTick,
            params.upperTick,
            params.liquidity,
            ""
        );
    }

    function uniswapV3MintCallback(uint256 amount0, uint256 amount1, bytes calldata data) public {
        if (transferInMintCallback) {
            UniswapV3Pool.CallbackData memory extra = abi.decode(data, (UniswapV3Pool.CallbackData));
            IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0);
            IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1);
        }
    }

    function setupTestCase(TestCaseParams memory params)
        internal
        returns (uint256 poolBalance0, uint256 poolBalance1)
    {
        token0.mint(address(this), params.wethBalance);
        token1.mint(address(this), params.usdcBalance);
        pool = new UniswapV3Pool(address(token0), address(token1), params.currentSqrtP, params.currentTick);
        if (params.mintLiquidity) {
            token0.approve(address(this), params.wethBalance);
            token1.approve(address(this), params.usdcBalance);
            UniswapV3Pool.CallbackData memory extra =
                UniswapV3Pool.CallbackData({token0: address(token0), token1: address(token1), payer: address(this)});
            (poolBalance0, poolBalance1) =
                pool.mint(address(this), params.lowerTick, params.upperTick, params.liquidity, abi.encode(extra));
        }
        transferInMintCallback = params.transferInMintCallback;
        transferInSwapCallback = params.transferInSwapCallback;
    }
}
