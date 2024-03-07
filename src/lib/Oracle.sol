// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

library Oracle {
    struct Observation {
        uint32 timestamp;
        int56 tickCumulative;
        bool initialized;
    }

    function initialize(Observation[65535] storage self, uint32 time) internal {}

    function write(
        Observation[65535] storage self,
        uint16 index,
        uint32 timestamp,
        int24 tick,
        uint16 cardinality,
        uint16 cardinalityNext
    ) internal returns (uint16 indexUpdated, uint16 cardinalityUpdated) {}

    function grow( Observation[65535] storage self, uint16 current, uint16 next) internal {}

    function transform(Observation memory last , uint32 timeStamp, int24 tick) internal pure returns (Observation memory) {}

    function lte(
        uint32 time,
        uint32 a,
        uint32 b
    ) private pure returns (bool) {
        // if there hasn't been overflow, no need to adjust
        if (a <= time && b <= time) return a <= b;

        uint256 aAdjusted = a > time ? a : a + 2**32;
        uint256 bAdjusted = b > time ? b : b + 2**32;

        return aAdjusted <= bAdjusted;
    }



}
