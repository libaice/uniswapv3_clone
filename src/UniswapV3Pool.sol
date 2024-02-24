pragma solidity ^0.8.14;

import {Tick} from "src/lib/Tick.sol";
import {Position} from "src/lib/Position.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IUniswapV3MintCallback} from "src/interfaces/IUniswapV3MintCallback.sol";
import {IUniswapV3SwapCallback} from "src/interfaces/IUniswapV3SwapCallback.sol";

error ZeroLiquidity();
error InsufficientInputAmount();
error InvalidTickRange();

contract UniswapV3Pool {
    using Tick for mapping(int24 => Tick.Info);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    event Mint(
        address sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        int128 liquidity,
        int24 tick
    );

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

    struct CallbackData {
        address token0;
        address token1;
        address payer;
    }

    constructor(address _token0, address _token1, uint160 _sqrtPriceX96, int24 _tick) {
        token0 = _token0;
        token1 = _token1;
        slot0 = Slot0({sqrtPriceX96: _sqrtPriceX96, tick: _tick});
    }

    function mint(address owner, int24 lowerTick, int24 upperTick, uint128 amount, bytes calldata data)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        if (lowerTick < MIN_TICK || upperTick > MAX_TICK || lowerTick >= upperTick) {
            revert("UniswapV3Pool: INVALID_TICK_RANGE");
        }
        if (amount == 0) revert ZeroLiquidity();
        ticks.update(lowerTick, amount);
        ticks.update(upperTick, amount);

        Position.Info storage position = positions.get(owner, lowerTick, upperTick);
        position.update(amount);

        amount0 = 0.99897661834742528 ether; // TODO: replace with calculation
        amount1 = 5000 ether; // TODO: replace with calculation

        liquidity += uint128(amount);

        uint256 balance0Before;
        uint256 balance1Before;

        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();

        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0, amount1, data);

        if (amount0 > 0 && balance0Before + amount0 > balance0()) revert InsufficientInputAmount();
        if (amount1 > 0 && balance1Before + amount1 > balance1()) revert InsufficientInputAmount();

        emit Mint(msg.sender, owner, lowerTick, upperTick, amount, amount0, amount1);
    }

    function swap(address recepient, bytes calldata data) public returns (int256 amount0, int256 amount1) {
        int24 nextTick = 85184;
        uint160 nextPrice = 5604469350942327889444743441197;

        amount0 = -0.008396714242162444 ether;
        amount1 = 42 ether;

        (slot0.tick, slot0.sqrtPriceX96) = (nextTick, nextPrice);

        IERC20(token0).transfer(recepient, uint256(-amount0));
        uint256 balance1Before = balance1();
        IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(int256(amount0), int256(amount1), data);
        if (balance1Before + uint256(amount1) > balance1()) revert InsufficientInputAmount();
        emit Swap(msg.sender, recepient, amount0, amount1, slot0.sqrtPriceX96, int128(liquidity), slot0.tick);
    }

    function balance0() internal returns (uint256 balance) {
        return IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal returns (uint256 balance) {
        return IERC20(token1).balanceOf(address(this));
    }
}
