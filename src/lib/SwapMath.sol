// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import {Math} from "./Math.sol";

library SwapMath {
    function computeSwapStep(
        uint160 sqrtRatioCurrentX96,
        uint160 sqrtRatioTargetX96,
        uint128 liquidity,
        uint256 amountRemaining
    ) internal pure returns (uint160 sqrtPriceNextX96, uint256 amountIn, uint256 amountOut) {
        bool zeroForOne = sqrtRatioCurrentX96 >= sqrtRatioTargetX96;

        amountIn = zeroForOne
            ? Math.calcAmount0Delta(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity)
            : Math.calcAmount1Delta(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity);

        if (amountRemaining >= amountIn) {
            sqrtPriceNextX96 = sqrtRatioTargetX96;
        } else {
            sqrtPriceNextX96 =
                Math.getNextSqrtPriceFromInput(sqrtRatioCurrentX96, liquidity, amountRemaining, zeroForOne);
        }
        amountIn = Math.calcAmount0Delta(sqrtRatioCurrentX96, sqrtPriceNextX96, liquidity);
        amountOut = Math.calcAmount1Delta(sqrtRatioCurrentX96, sqrtPriceNextX96, liquidity);
        if (!zeroForOne) {
            (amountIn, amountOut) = (amountOut, amountIn);
        }
    }
}
