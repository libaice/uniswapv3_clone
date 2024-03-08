// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import {IUniswapV3Pool} from "src/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Manager} from "src/interfaces/IUniswapV3Manager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

import {IUniswapV3Manager} from "src/interfaces/IUniswapV3Manager.sol";
import {PoolAddress} from "src/lib/PoolAddress.sol";
import {Path} from "src/lib/Path.sol";
import {TickMath} from "src/lib/TickMath.sol";
import {LiquidityMath} from "src/lib/LiquidityMath.sol";

contract UniswapV3Manager is IUniswapV3Manager {
    using Path for bytes;

    error SlippageCheckFailed(uint256 amount0, uint256 amount1);
    error TooLittleReceived(uint256 amountOut);

    address public immutable factory;

    constructor(address factory_) {
        factory = factory_;
    }

    function getPosition(GetPositionParams calldata params)
        external
        view
        returns (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        IUniswapV3Pool pool = getPool(params.tokenA, params.tokenB, params.fee);
        (liquidity, feeGrowthInside0LastX128, feeGrowthInside1LastX128, tokensOwed0, tokensOwed1) =
            pool.positions(keccak256(abi.encodePacked(params.owner, params.lowerTick, params.upperTick)));
    }

    function getPool(address token0, address token1, uint24 fee) internal view returns (IUniswapV3Pool pool) {
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, token0, token1, fee));
    }

    function mint(MintParams calldata params) public returns (uint256 amount0, uint256 amount1) {
        IUniswapV3Pool pool = getPool(params.tokenA, params.tokenB, params.fee);
        (uint160 sqrtPriceX96,,,,) = pool.slot0();
        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(params.lowerTick);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(params.upperTick);
        uint128 liquidity = LiquidityMath.getLiquidityForAmounts(
            sqrtPriceX96, sqrtPriceLowerX96, sqrtPriceUpperX96, params.amount0Desired, params.amount1Desired
        );
        (amount0, amount1) = pool.mint(
            msg.sender,
            params.lowerTick,
            params.upperTick,
            liquidity,
            abi.encode(IUniswapV3Pool.CallbackData({token0: params.tokenA, token1: params.tokenB, payer: msg.sender}))
        );

        if (amount0 < params.amount0Min || amount1 < params.amount1Min) {
            revert SlippageCheckFailed(amount0, amount1);
        }
    }

    function swapSingle(SwapSingleParams calldata params) public returns (uint256 amountOut) {
        amountOut = _swap(
            params.amountIn,
            msg.sender,
            params.sqrtPriceLimitX96,
            SwapCallbackData({path: abi.encodePacked(params.tokenIn, params.tokenOut, params.fee), payer: msg.sender})
        );
    }

    function swap(SwapParams memory params) public returns (uint256 amountOut) {
        address payer = msg.sender;
        bool hasMultiplePools;

        while (true) {
            hasMultiplePools = params.path.hasMultiplePools();
            params.amountIn = _swap(
                params.amountIn,
                hasMultiplePools ? address(this) : params.recipient,
                0,
                SwapCallbackData({path: params.path.getFirstPool(), payer: payer})
            );

            if (hasMultiplePools) {
                payer = address(this);
                params.path = params.path.skipToken();
            } else {
                amountOut = params.amountIn;
                break;
            }
        }
        if (amountOut < params.minAmountOut) {
            revert TooLittleReceived(amountOut);
        }
    }

    function _swap(uint256 amountIn, address recipient, uint160 sqrtPriceLimitX96, SwapCallbackData memory data)
        internal
        returns (uint256 amountOut)
    {
        (address tokenIn, address tokenOut, uint24 tickSpacing) = data.path.decodeFirstPool();
        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0, int256 amount1) = getPool(tokenIn, tokenOut, tickSpacing).swap(
            recipient,
            zeroForOne,
            amountIn,
            sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : sqrtPriceLimitX96,
            abi.encode(data)
        );
        amountOut = uint256(-(zeroForOne ? amount1 : amount0));
    }

    // multiple pool , think of swap path

    function uniswapMintCallback(uint256 amount0, uint256 amount1, bytes calldata data) public {
        IUniswapV3Pool.CallbackData memory extra = abi.decode(data, (IUniswapV3Pool.CallbackData));
        IERC20(extra.token0).transferFrom(extra.payer, msg.sender, amount0);
        IERC20(extra.token1).transferFrom(extra.payer, msg.sender, amount1);
    }

    function uniswapV3SwapCallback(int256 amount0, int256 amount1, bytes calldata data) public {
        IUniswapV3Pool.CallbackData memory extra = abi.decode(data, (IUniswapV3Pool.CallbackData));
        if (amount0 > 0) {
            IERC20(extra.token0).transferFrom(extra.payer, msg.sender, uint256(amount0));
        }
        if (amount1 > 0) {
            IERC20(extra.token1).transferFrom(extra.payer, msg.sender, uint256(amount1));
        }
    }
}
