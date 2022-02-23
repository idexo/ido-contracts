// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

library StakeMath {
    /**
     * @dev Returns StakeToken multiplier.
     *
     * @param tokenId the tokenId to check
     *
     * 0 < `tokenId` <300: 120.
     * 300 <= `tokenId` <4000: 110.
     * 4000 <= `tokenId`: 100.
     */
    function multiplier(uint256 tokenId) internal pure returns (uint256) {
        if (tokenId < 300) {
            return 120;
        } else if (300 <= tokenId && tokenId < 4000) {
            return 110;
        } else {
            return 100;
        }
    }
}
