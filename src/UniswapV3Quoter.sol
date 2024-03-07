// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.14;

import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {Path} from "./lib/Path.sol";
import {PoolAddress} from "./lib/PoolAddress.sol";
import {TickMath} from "./lib/TickMath.sol";

contract UniswapV3Quoter {
    using Path for bytes;

    struct QuoteSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 tickSpacing;
        uint256 amountIn;
        uint160 sqrtPriceLimitX96;
    }

    address public immutable factory;

    constructor(address _factory) {
        factory = _factory;
    }

    function quote(bytes memory path, uint256 amountIn)
        public
        returns (uint256 amountOut, uint160[] memory sqrtPriceXAfterList, int24[] memory tickAfterList)
    {
        sqrtPriceXAfterList = new uint160[](path.numPools());
        tickAfterList = new int24[](path.numPools());

        uint256 i = 0;
        while (true) {
            (address tokenIn, uint24 tickSpacing, address tokenOut) = path.decodeFirstPool();
            (uint256 amountOut_, uint160 sqrtPriceX96After, int24 tickAfter) = quoteSingle(
                QuoteSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    tickSpacing: tickSpacing,
                    amountIn: amountIn,
                    sqrtPriceLimitX96: 0
                })
            );

            sqrtPriceXAfterList[i] = sqrtPriceX96After;
            tickAfterList[i] = tickAfter;
            amountIn = amountOut_;
            i++;

            if (path.hasMultiplePools()) {
                path = path.skipToken();
            } else {
                amountOut = amountIn;
                break;
            }
        }
    }

    function quoteSingle(QuoteSingleParams memory params)
        public
        returns (uint256 amountOut, uint160 sqrtPriceX96After, int24 tickAfter)
    {
        IUniswapV3Pool pool = getPool(params.tokenIn, params.tokenOut, params.tickSpacing);
        bool zeroForOne = params.tokenIn < params.tokenOut;
        try pool.swap(
            address(this),
            zeroForOne,
            params.amountIn,
            params.sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : params.sqrtPriceLimitX96,
            abi.encode(address(pool))
        ) {} catch (bytes memory reason) {
            return abi.decode(reason, (uint256, uint160, int24));
        }
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes memory data) external view {
        address pool = abi.decode(data, (address));
        uint256 amountOut = amount0Delta > 0 ? uint256(-amount0Delta) : uint256(-amount1Delta);
        (uint160 sqrtPriceX96After, int24 tickAfter) = IUniswapV3Pool(pool).slot0();
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, amountOut)
            mstore(add(ptr, 0x20), sqrtPriceX96After)
            mstore(add(ptr, 0x40), tickAfter)
            revert(ptr, 0x60)
        }
    }

    function getPool(address token0, address token1, uint24 tickSpacing) internal view returns (IUniswapV3Pool pool) {
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, token0, token1, tickSpacing));
    }
}
