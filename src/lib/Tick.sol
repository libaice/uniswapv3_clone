pragma solidity ^0.8.14;

import "./LiquidityMath.sol";
import "./Math.sol";

library Tick {
    struct Info {
        bool initialized;
        // totalLiquidityAtTick
        uint128 liquidityGross;

        // amount of liqudiity added or subtracted when tick is crossed
        int128 liquidityNet;

        // fee growth per unit of liquidity
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
    }

    function update(
        mapping(int24 => Tick.Info) storage self, 
        int24 tick, 
        int24 currentTick,
        int128 liquidityDelta, 
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        bool upper
        )
        internal
        returns (bool flipped)
    {
        Tick.Info storage tickInfo = self[tick];

        uint128 liquidityBefore = tickInfo.liquidityGross;
        uint128 liquidityAfter = LiquidityMath.addLiquidity(liquidityBefore, liquidityDelta);
        flipped = (liquidityBefore == 0) != (liquidityAfter == 0);
        // update liquidity Data
        if (liquidityBefore == 0) {
            if(tick <= currentTick){
                 // by convention, assume that all previous fees were collected below
                tickInfo.feeGrowthOutside0X128 = feeGrowthGlobal0X128;
                tickInfo.feeGrowthOutside1X128 = feeGrowthGlobal1X128;
            }
            tickInfo.initialized = true;
        }
        tickInfo.liquidityGross = liquidityAfter;
        tickInfo.liquidityNet = upper
            ? int128(int256(tickInfo.liquidityNet) - liquidityDelta)
            : int128(int256(tickInfo.liquidityNet) + liquidityDelta);
    }

    function cross(mapping(int24 => Tick.Info) storage self, int24 tick)
        internal
        view
        returns (int128 liquidityDelta)
    {
        Tick.Info storage info = self[tick];
        liquidityDelta = info.liquidityNet;
    }
}
