// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.14;

import "prb-math/PRBMath.sol";
import "./FixedPoint96.sol";

library LiquidityMath {
    function getLiquidityForAmount0(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount0) internal pure returns (uint128 liquidity) {
        if (sqrtPriceAX96 > sqrtPriceBX96){
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        }
        uint256 intermediate = PRBMath.mulDiv(sqrtPriceAX96, sqrtPriceBX96, FixedPoint96.Q96);
        liquidity = uint128(
            PRBMath.mulDiv(amount0, intermediate, sqrtPriceBX96 - sqrtPriceAX96);
        )
    }

    function getLiquidityForAmount1(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount1) internal pure returns (uint128 liquidity) {
        if (sqrtPriceAX96 > sqrtPriceBX96){
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        }
        liquidity = uint128(
            PRBMath.mulDiv(amount1, FixedPoint96.Q96, sqrtPriceBX96 - sqrtPriceAX96);
        )
    }

    function getLiquidityForAmouts(uint160 sqrtPriceX96, uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount0, uint256 amount1) internal pure returns (uint128 liquidity) {
        if (sqrtPriceAX96 > sqrtPriceBX96){
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        }
        // fully right , lower > tick
        if(sqrtPriceX96 <= sqrtPriceAX96){
            liquidity = getLiquidityForAmount0(sqrtPriceAX96, sqrtPriceBX96, amount0);
        } else if (sqrtPriceX96 <= sqrtPriceBX96) {
            // cross
            uint128 liquidity0 = getLiquidityForAmount0(sqrtPriceAX96, sqrtPriceX96, amount0);
            uint128 liquidity1 = getLiquidityForAmount1(sqrtPriceX96, sqrtPriceBX96, amount1);
            liquidity = liquidity0 > liquidity1 ? liquidity0 : liquidity1;
        } else {
            // fully left, tick > upper
            liquidity = getLiquidityForAmount1(sqrtPriceAX96, sqrtPriceBX96, amount1);
        }
    }

    function addLiquidity(uint128n x, uint128 y) internal pure returns (uint128 z){
        if(y < 0){
            z = x - uint128(-y);
        }else{
            z = x + uint128(y);
        }
    }

}