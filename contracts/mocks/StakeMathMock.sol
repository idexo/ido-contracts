// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "../lib/StakeMath.sol";

contract StakeMathMock {
    using StakeMath for uint256;

    function multiplier(uint256 tokenId) public pure returns (uint256) {
        return tokenId.multiplier();
    }

    function boost(uint256 term) public pure returns (uint256) {
        return term.boost();
    }
}
