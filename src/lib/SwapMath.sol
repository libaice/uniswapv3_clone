// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "prb-math/PRBMath.sol";
import {Math} from "./Math.sol";

library SwapMath {
    function computeSwapStep(
        uint160 sqrtRatioCurrentX96,
        uint160 sqrtRatioTargetX96,
        uint128 liquidity,
        uint256 amountRemaining,
        uint24 fee
    ) internal pure returns (uint160 sqrtPriceNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount) {
        bool zeroForOne = sqrtRatioCurrentX96 >= sqrtRatioTargetX96;
        // fee decimal is 1e6, 0.3% fee is 3000
        uint256 amountRemaingLessFee = PRBMath.mulDiv(amountRemaining, 1e6 - fee, 1e6);
        amountIn = zeroForOne
            ? Math.calcAmount0Delta(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, true)
            : Math.calcAmount1Delta(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, true);

        if (amountRemaingLessFee >= amountIn) {
            sqrtPriceNextX96 = sqrtRatioTargetX96;
        } else {
            sqrtPriceNextX96 =
                Math.getNextSqrtPriceFromInput(sqrtRatioCurrentX96, liquidity, amountRemaingLessFee, zeroForOne);
        }

        bool max = sqrtPriceNextX96 == sqrtRatioTargetX96;

        if (zeroForOne) {
            amountIn = max ? amountIn : Math.calcAmount0Delta(sqrtRatioCurrentX96, sqrtPriceNextX96, liquidity, true);
            amountOut = Math.calcAmount1Delta(sqrtRatioCurrentX96, sqrtPriceNextX96, liquidity, false);
        } else {
            amountIn = max ? amountIn : Math.calcAmount1Delta(sqrtRatioCurrentX96, sqrtPriceNextX96, liquidity, true);
            amountOut = Math.calcAmount0Delta(sqrtRatioCurrentX96, sqrtPriceNextX96, liquidity, false);
        }

        if (!max) {
            feeAmount = amountRemaining - amountIn;
        } else {
            feeAmount = Math.mulDivRoundingUp(amountIn, fee, 1e6 - fee);
        }
    }
}
