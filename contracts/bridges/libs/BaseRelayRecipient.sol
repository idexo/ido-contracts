// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

/**
 * A base contract to be inherited by any contract that want to receive relayed transactions
 * A subclass must use `_msgSender()` instead of `msg.sender`
 */
abstract contract BaseRelayRecipient {

    /*
     * Forwarder singleton we accept calls from
     */
    address public trustedForwarder;

    /*
     * Require a function to be called through GSN only
     */
    modifier trustedForwarderOnly() {
        require(msg.sender == address(trustedForwarder), "BaseRelayRecipient: CALLER_NO_TRUSTED_FORWARDER");
        _;
    }

    /**
     * Check if `forwarder` address is `trustedForwarder`
     */
    function isTrustedForwarder(address forwarder) public view returns(bool) {
        return forwarder == trustedForwarder;
    }

    /**
     * Return the sender of this call.
     * If the call came through our trusted forwarder, return the original sender.
     * otherwise, return `msg.sender`.
     * should be used in the contract anywhere instead of `msg.sender`
     */
    function _msgSender() internal virtual view returns (address ret) {
        if (msg.data.length >= 24 && isTrustedForwarder(msg.sender)) {
            // At this point we know that the sender is a trusted forwarder,
            // so we trust that the last bytes of `msg.data` are the verified sender address.
            // extract sender address from the end of `msg.data`
            assembly {
                ret := shr(96,calldataload(sub(calldatasize(),20)))
            }
        } else {
            return msg.sender;
        }
    }
}
