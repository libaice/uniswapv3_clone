// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "prb-math/PRBMath.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IUniswapV3Pool} from "src/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3PoolDeployer} from "src/interfaces/IUniswapV3PoolDeployer.sol";
import {IUniswapV3MintCallback} from "src/interfaces/IUniswapV3MintCallback.sol";
import {IUniswapV3SwapCallback} from "src/interfaces/IUniswapV3SwapCallback.sol";
import {IUniswapV3FlashCallback} from "src/interfaces/IUniswapV3FlashCallback.sol";

import {LiquidityMath} from "src/lib/LiquidityMath.sol";
import {FixedPoint128} from "src/lib/FixedPoint128.sol";
import {Tick} from "src/lib/Tick.sol";
import {Position} from "src/lib/Position.sol";
import {TickBitmap} from "src/lib/TickBitmap.sol";
import {Math} from "src/lib/Math.sol";
import {Oracle} from "src/lib/Oracle.sol";
import {TickMath} from "src/lib/TickMath.sol";
import {SwapMath} from "src/lib/SwapMath.sol";

contract UniswapV3Pool is IUniswapV3Pool {
    using Oracle for Oracle.Observation[65535];
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    error AlreadyInitialized();
    error FlashLoanNotPaid();
    error InsufficientInputAmount(); 
    error InvalidPriceLimit();
    error InvalidTickRange();
    error NotEnoughLiquidity();
    error ZeroLiquidity();

    event Burn(
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    event Collect(
        address indexed owner,
        address recipient,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount0,
        uint128 amount1
    );

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

    event IncreaseObservationCardinalityNext(
        uint16 observationCardinalityNextOld, uint16 observationCardinalityNextNew
    );

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    // Pool Parameters
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable tickSpacing;
    uint24 public immutable fee;

    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;

    struct Slot0 {
        // current sqrt(P)
        uint160 sqrtPriceX96;
        // current tick
        int24 tick;
        //most recent observation index
        uint16 observationIndex;
        //cardinality of observations
        uint16 observationCardinality;
        // next maximum cardinality of observations
        uint16 observationCardinalityNext;
    }

    struct SwapState {
        uint256 amountSpecifiedRemaining;
        uint256 amountCalculated;
        uint160 sqrtPriceX96;
        int24 tick;
        uint256 feeGrowthGlobalX128;
        uint128 liquidity;
    }

    struct StepState {
        uint160 sqrtPriceStartX96;
        int24 nextTick;
        bool initialized;
        uint160 sqrtPriceNextX96;
        uint256 amountIn;
        uint256 amountOut;
        uint256 feeAmount;
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
    Oracle.Observation[65535] public observations;

    constructor() {
        (factory, token0, token1, tickSpacing, fee) = IUniswapV3PoolDeployer(msg.sender).parameters();
    }

    function initialize(uint160 sqrtPriceX96) public {
        if (slot0.sqrtPriceX96 != 0) revert AlreadyInitialized();
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        (uint16 cardinality, uint16 cardinalityNext) = observations.initialize(_blockTimestamp());
        slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex: 0,
            observationCardinality: cardinality,
            observationCardinalityNext: cardinalityNext
        });
    }

    struct ModifyPositionParams {
        address owner;
        int24 lowerTick;
        int24 upperTick;
        int128 liquidityDelta;
    }

    function _modifyPosition(ModifyPositionParams memory params)
        internal
        returns (Position.Info storage position, int256 amount0, int256 amount1)
    {
        // 1. 使用缓存来减少SLOAD， 优化gas
        Slot0 memory slot0_ = slot0;
        uint256 feeGrowthGlobal0X128_ = feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128_ = feeGrowthGlobal1X128;

        // 2. 获取用户当前的仓位
        position = positions.get(params.owner, params.lowerTick, params.upperTick);

        // 3. 计算是否需要更新仓位
        bool flippedLower = ticks.update(
            params.lowerTick,
            slot0_.tick,
            int128(params.liquidityDelta),
            feeGrowthGlobal0X128_,
            feeGrowthGlobal1X128_,
            false
        );
        bool flippedUpper = ticks.update(
            params.upperTick,
            slot0_.tick,
            int128(params.liquidityDelta),
            feeGrowthGlobal0X128_,
            feeGrowthGlobal1X128_,
            true
        );

        // 4. 如果需要切换方向， 更换方向
        if (flippedLower) {
            tickBitmap.flipTick(params.lowerTick, 1);
        }
        if (flippedUpper) {
            tickBitmap.flipTick(params.upperTick, 1);
        }
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = ticks.getFeeGrowthInside(
            params.lowerTick, params.upperTick, slot0_.tick, feeGrowthGlobal0X128_, feeGrowthGlobal1X128_
        );

        position.update(params.liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128);

        // 5. 分阶段进行流动性的添加
        if (slot0_.tick < params.lowerTick) {
            amount0 = int256(
                Math.calcAmount0Delta(
                    TickMath.getSqrtRatioAtTick(params.lowerTick),
                    TickMath.getSqrtRatioAtTick(params.upperTick),
                    params.liquidityDelta
                )
            );
        } else if (slot0_.tick < params.upperTick) {
            amount0 = int256(
                Math.calcAmount0Delta(
                    slot0_.sqrtPriceX96, TickMath.getSqrtRatioAtTick(params.upperTick), params.liquidityDelta
                )
            );
            amount1 = Math.calcAmount1Delta(TickMath.getSqrtRatioAtTick(params.lowerTick), slot0_.sqrtPriceX96, params.liquidityDelta);
            liquidity = LiquidityMath.addLiquidity(liquidity, params.liquidityDelta);
        } else {
            amount1 = Math.calcAmount1Delta(
                TickMath.getSqrtRatioAtTick(params.lowerTick),
                TickMath.getSqrtRatioAtTick(params.upperTick),
                params.liquidityDelta
            );
        }
    }

    function mint(address owner, int24 lowerTick, int24 upperTick, uint128 amount, bytes calldata data)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        // 1.两个tick 在区间内
        if (lowerTick < MIN_TICK || upperTick > MAX_TICK || lowerTick >= upperTick) {
            revert("UniswapV3Pool: INVALID_TICK_RANGE");
        }
        if (amount == 0) revert ZeroLiquidity();

        // 2. 更新仓位
        (, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: owner,
                lowerTick: lowerTick,
                upperTick: upperTick,
                liquidityDelta: int128(amount)
            })
        );

        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        uint256 balance0Before;
        uint256 balance1Before;

        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();

        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0, amount1, data);

        if (amount0 > 0 && balance0Before + amount0 > balance0()) revert InsufficientInputAmount();
        if (amount1 > 0 && balance1Before + amount1 > balance1()) revert InsufficientInputAmount();

        emit Mint(msg.sender, owner, lowerTick, upperTick, amount, amount0, amount1);
    }

    function swap(
        address recepient,
        bool zeroForOne,
        uint256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) public returns (int256 amount0, int256 amount1) {
        // 1. cache for gas saving
        Slot0 memory slot0_ = slot0;
        uint128 liquidity_ = liquidity;

        // 2. 判断方向， 价格是否合法
        if (
            zeroForOne
                ? sqrtPriceLimitX96 > slot0_.sqrtPriceX96 || sqrtPriceLimitX96 < TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 < slot0_.sqrtPriceX96 || sqrtPriceLimitX96 > TickMath.MAX_SQRT_RATIO
        ) {
            revert InvalidPriceLimit();

            SwapState memory state = SwapState({
                amountSpecifiedRemaining: amountSpecified,
                amountCalculated: 0,
                sqrtPriceX96: slot0_.sqrtPriceX96,
                tick: slot0_.tick,
                feeGrowthGlobalX128: zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128,
                liquidity: liquidity_
            });

            while (state.amountSpecifiedRemaining > 0 && state.sqrtPriceX96 != sqrtPriceLimitX96) {
                StepState memory step;

                step.sqrtPriceStartX96 = state.sqrtPriceX96;

                (step.nextTick,) =
                    tickBitmap.nextInitializedTickWithinOneWord(state.tick, int24(tickSpacing), zeroForOne);

                step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.nextTick);

                (state.sqrtPriceX96, step.amountIn, step.amountOut) = SwapMath.computeSwapStep(
                    state.sqrtPriceX96,
                    (zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : step.sqrtPriceNextX96 > sqrtPriceLimitX96)
                        ? sqrtPriceLimitX96
                        : step.sqrtPriceNextX96,
                    state.liquidity,
                    state.amountSpecifiedRemaining,
                    fee
                );
                state.amountSpecifiedRemaining -= step.amountIn + step.feeAmount;
                state.amountCalculated += step.amountOut;

                if (state.liquidity > 0) {
                    state.feeGrowthGlobalX128 += PRBMath.mulDiv(step.feeAmount, FixedPoint128.Q128, state.liquidity);
                }

                if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                    if (step.initialized) {
                        int128 liquidityDelta = ticks.cross(
                            step.nextTick,
                            (zeroForOne ? state.feeGrowthGlobalX128 : feeGrowthGlobal0X128),
                            (zeroForOne ? feeGrowthGlobal1X128 : state.feeGrowthGlobalX128)
                        );

                        if (zeroForOne) liquidityDelta = -liquidityDelta;

                        state.liquidity = LiquidityMath.addLiquidity(state.liquidity, liquidityDelta);

                        if (state.liquidity == 0) revert NotEnoughLiquidity();
                    }

                    state.tick = zeroForOne ? step.nextTick - 1 : step.nextTick;
                } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                    state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
                }
            }

            if (state.tick != slot0_.tick) {
                (uint16 observationIndex, uint16 observationCardinality) = observations.write(
                    slot0_.observationIndex,
                    _blockTimestamp(),
                    slot0_.tick,
                    slot0_.observationCardinality,
                    slot0_.observationCardinalityNext
                );

                (slot0.sqrtPriceX96, slot0.tick, slot0.observationIndex, slot0.observationCardinality) =
                    (state.sqrtPriceX96, state.tick, observationIndex, observationCardinality);
            } else {
                slot0.sqrtPriceX96 = state.sqrtPriceX96;
            }

            if (liquidity_ != state.liquidity) {
                liquidity = state.liquidity;
            }

            if (zeroForOne) {
                feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
            } else {
                feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
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
            emit Swap(msg.sender, recepient, amount0, amount1, slot0.sqrtPriceX96, int128(liquidity), slot0.tick);
        }
    }

    function flash(uint256 amount0, uint256 amount1, bytes calldata data) external {
        uint256 fee0 = Math.mulDivRoundingUp(amount0, fee, 1e6);
        uint256 fee1 = Math.mulDivRoundingUp(amount1, fee, 1e6);

        uint256 balance0Before = IERC20(token0).balanceOf(address(this));
        uint256 balance1Before = IERC20(token1).balanceOf(address(this));

        if (amount0 > 0) IERC20(token0).transfer(msg.sender, amount0);
        if (amount1 > 0) IERC20(token1).transfer(msg.sender, amount1);

        IUniswapV3FlashCallback(msg.sender).uniswapV3FlashCallback(fee0, fee1, data);
        if (IERC20(token0).balanceOf(address(this)) < balance0Before + fee0) revert FlashLoanNotPaid();
        if (IERC20(token1).balanceOf(address(this)) < balance1Before + fee1) revert FlashLoanNotPaid();

        emit Flash(msg.sender, amount0, amount1);
    }

    function observe(uint32[] calldata secondsAgos) public view returns (int56[] memory tickCumulatives) {
        return observations.observe(
            _blockTimestamp(), secondsAgos, slot0.tick, slot0.observationIndex, slot0.observationCardinality
        );
    }

    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external {
        uint16 observationCardinalityNextOld = slot0.observationCardinalityNext;
        uint16 observationCardinalityNextNew =
            observations.grow(observationCardinalityNextOld, observationCardinalityNext);
        if (observationCardinalityNextNew != observationCardinalityNextOld) {
            slot0.observationCardinalityNext = observationCardinalityNextNew;
            emit IncreaseObservationCardinalityNext(observationCardinalityNextOld, observationCardinalityNextNew);
        }
    }

    function balance0() internal returns (uint256 balance) {
        return IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal returns (uint256 balance) {
        return IERC20(token1).balanceOf(address(this));
    }

    function _blockTimestamp() internal view returns (uint32 timestamp) {
        timestamp = uint32(block.timestamp);
    }
}
