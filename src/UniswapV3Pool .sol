pragma solidity ^0.8.14;

import {Tick} from "src/lib/Tick.sol";
import {Position} from "src/lib/Position.sol";

error ZeroLiquidity();

contract UniswapV3Pool {
    using Tick for mapping(int24 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;
    
    // Pool Token
    address public immutable token0;
    address public immutable token1;

    struct Slot0 {
        uint160 sqrtPriceX96;
        int24 tick;
    }

    Slot0 public slot0;

    // Amount of Liquidity
    uint128 public liquidity;

    //Tick Info
    mapping(int24 => Tick.Info) public ticks;

    //Position Info
    mapping(bytes32 => Position.Info) public positions;


    constructor(
        address _token0, 
        address _token1,
        uint160 _sqrtPriceX96,
        int24 _tick
    ) {
        token0 = _token0;
        token1 = _token1;
        slot0 = Slot0({
            sqrtPriceX96: _sqrtPriceX96,
            tick: _tick
        });
    }

    function mint(
        address owner, 
        int24 lowerTick,
        int24 upperTick,
        uint128 amount
    ) external returns(uint256 amount0, uint256 amount1) {
        if(lowerTick < MIN_TICK || upperTick > MAX_TICK || lowerTick >= upperTick) {
            revert("UniswapV3Pool: INVALID_TICK_RANGE");
        }
        if(amount == 0) revert ZeroLiquidity();
    }

}