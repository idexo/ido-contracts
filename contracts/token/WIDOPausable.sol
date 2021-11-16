// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "../lib/Blacklist.sol";

contract WIDOPausable is ERC20Permit, Blacklist {
  // Cross-chain transfer relayer contract address
  address public relayer;

  event RelayerAddressChanged(address indexed relayer);
  
  constructor() ERC20("Wrapped Idexo Token Pausable", "WIDOP") ERC20Permit("Wrapped Idexo Token Pausable") { }

  /**************************|
  |          Setters         |
  |_________________________*/

  /**
    * @dev Set relayer address
    * Only owner can call
    */
  function setRelayer(address newRelayer) external onlyOwner {
    require(newRelayer != address(0), "WIDOPausable: NEW_RELAYER_ADDRESS_INVALID");
    relayer = newRelayer;

    emit RelayerAddressChanged(newRelayer);
  }  

  /************************|
  |          Token         |
  |_______________________*/

  /**
    * @dev Mint new WIDO
    * Only relayer can call
    */
  function mint(
    address account,
    uint256 amount
  ) external {
    require(msg.sender == relayer, "WIDOPausable: CALLER_NO_RELAYER");
    _mint(account, amount);
  }

  /**
    * @dev Burn WIDO
    * Only relayer can call
    */
  function burn(
    address account,
    uint256 amount
  ) external {
    require(msg.sender == relayer, "WIDOPausable: CALLER_NO_RELAYER");
    _burn(account, amount);
  }

  /**
    * @dev Get chain id.
    */
  function getChainId() public view returns (uint256) {
    uint256 id;
    assembly { id := chainid() }
    return id;
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal virtual override {
    require(!blacklist[msg.sender], "WIDOPausable: CALLER_BLACKLISTED");
    require(!blacklist[from], "WIDOPausable: FROM_ADDRESS_BLACKLISTED");
    super._beforeTokenTransfer(from, to, amount);
  }
}
