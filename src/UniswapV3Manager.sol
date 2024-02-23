pragma solidity ^0.8.14;

import {UniswapV3Pool} from "src/UniswapV3Pool.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract UniswapV3Manager {
    function mint(
        address poolAddress_,
        int24 lowerTick,
        int24 upperTick,
        uint128 liquidity,
        bytes calldata data
    )public{
        UniswapV3Pool(poolAddress_).mint(msg.sender, lowerTick, upperTick, liquidity, data);
    }

    function swap(address poolAddress_, bytes calldata data) public {
        UniswapV3Pool(poolAddress_).swap(msg.sender, data);
    }
}