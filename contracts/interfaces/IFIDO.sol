// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFIDO is IERC20 {
    function setRelayer(address newRelayer) external;

    function renounceOwnership() external;

    function transferOwnership(address _newOwner) external;

    function acceptOwnership() external;

    function mint(
        address account,
        uint256 amount
    ) external;

    function burn(
        address account,
        uint256 amount
    ) external;

    function getChainId() external view returns (uint256);
}
