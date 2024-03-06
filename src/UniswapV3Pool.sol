pragma solidity ^0.8.14;

import {Tick} from "src/lib/Tick.sol";
import {Position} from "src/lib/Position.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IUniswapV3MintCallback} from "src/interfaces/IUniswapV3MintCallback.sol";
import {IUniswapV3SwapCallback} from "src/interfaces/IUniswapV3SwapCallback.sol";
import {TickBitmap} from "src/lib/TickBitmap.sol";
import {Math} from "src/lib/Math.sol";
import {TickMath} from "src/lib/TickMath.sol";
import {SwapMath} from "src/lib/SwapMath.sol";

error ZeroLiquidity();
error InsufficientInputAmount();
error InvalidTickRange();

contract UniswapV3Pool {
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
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

    event Flash(address indexed recipient, uint256 amount0, uint256 amount1);

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    // Pool Token
    address public immutable token0;
    address public immutable token1;

    struct Slot0 {
        // current sqrt(P)
        uint160 sqrtPriceX96;
        // current tick
        int24 tick;
    }

    struct CallbackData {
        address token0;
        address token1;
        address payer;
    }

    struct SwapState {
        uint256 amountSpecifiedRemaining;
        uint256 amountCalculated;
        uint160 sqrtPriceX96;
        int24 tick;
    }

    struct StepState {
        uint160 sqrtPriceStartX96;
        int24 nextTick;
        uint160 sqrtPriceNextX96;
        uint256 amountIn;
        uint256 amountOut;
    }

    Slot0 public slot0;

    // Amount of Liquidity
    uint128 public liquidity;

    //Tick Info
    mapping(int24 => Tick.Info) public ticks;
    // TickBitMap Info
    mapping(int16 => uint256) public tickBitmap;
    //Position Info
    mapping(bytes32 => Position.Info) public positions;

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

        bool flippedLower = ticks.update(lowerTick, int128(amount), false);
        bool flippedUpper = ticks.update(upperTick, int128(amount), true);

        if (flippedLower) {
            tickBitmap.flipTick(lowerTick, 1);
        }
        if (flippedUpper) {
            tickBitmap.flipTick(upperTick, 1);
        }

        Position.Info storage position = positions.get(owner, lowerTick, upperTick);
        position.update(amount);

        amount0 = Math.calcAmount0Delta(slot0.sqrtPriceX96, TickMath.getSqrtRatioAtTick(upperTick), amount);

        amount1 = Math.calcAmount1Delta(slot0.sqrtPriceX96, TickMath.getSqrtRatioAtTick(lowerTick), amount);

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

    function swap(address recepient, bool zeroForOne, uint256 amountSpecified, bytes calldata data)
        public
        returns (int256 amount0, int256 amount1)
    {
        Slot0 memory slot0_ = slot0;
        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: slot0_.sqrtPriceX96,
            tick: slot0_.tick
        });

        while (state.amountSpecifiedRemaining > 0) {
            StepState memory step;
            step.sqrtPriceStartX96 = state.sqrtPriceX96;
            (step.nextTick,) = tickBitmap.nextInitializedTickWithinOneWord(state.tick, 1, zeroForOne);
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.nextTick);

            (state.sqrtPriceX96, step.amountIn, step.amountOut) = SwapMath.computeSwapStep(
                step.sqrtPriceStartX96, step.sqrtPriceNextX96, liquidity, state.amountSpecifiedRemaining
            );
            state.amountSpecifiedRemaining -= step.amountIn;
            state.amountCalculated += step.amountOut;
            state.tick = TickMath.getTickAtSqrtRatio(step.sqrtPriceNextX96);
        }

        if (state.tick != slot0_.tick) {
            (slot0.sqrtPriceX96, slot0.tick) = (state.sqrtPriceX96, state.tick);
        }

        (amount0, amount1) = zeroForOne
            ? (int256(amountSpecified - state.amountSpecifiedRemaining), -int256(state.amountCalculated))
            : (-int256(state.amountCalculated), int256(amountSpecified - state.amountSpecifiedRemaining));

        if (zeroForOne) {
            IERC20(token1).transfer(recepient, uint256(-amount1));
            uint256 balance0Before = balance0();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
            if (balance0Before + uint256(amount0) > balance0()) revert InsufficientInputAmount();
        } else {
            IERC20(token0).transfer(recepient, uint256(-amount0));
            uint256 balance1Before = balance1();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
            if (balance1Before + uint256(amount1) > balance1()) revert InsufficientInputAmount();
        }

        // IERC20(token0).transfer(recepient, uint256(-amount0));
        // uint256 balance1Before = balance1();
        // IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(int256(amount0), int256(amount1), data);
        // if (balance1Before + uint256(amount1) > balance1()) revert InsufficientInputAmount();
        emit Swap(msg.sender, recepient, amount0, amount1, slot0.sqrtPriceX96, int128(liquidity), slot0.tick);
    }

    function balance0() internal returns (uint256 balance) {
        return IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal returns (uint256 balance) {
        return IERC20(token1).balanceOf(address(this));
    }
}
