// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.14;

import {ERC721} from "solmate/tokens/ERC721.sol";

contract UniswapV3NFTManager is ERC721 {
    error NotAuthorized();
    error NotEnoughLiquidity();
    error PositionNotCleared();
    error SlippageCheckFailed(uint256 amount0, uint256 amount1);
    error WrongToken();

    address public immutable factory;

    constructor(address factoryAddress) ERC721("Uniswap V3 Positions", "UNIV3") {
        factory = factoryAddress;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return "";
    }
}
