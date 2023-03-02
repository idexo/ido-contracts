// Initiate `ownerPrivateKey` with the first account private key on test evm

const { expect, assert } = require("chai")
const truffleAssert = require("truffle-assertions")
const { BN, constants, expectEvent, expectRevert } = require("@openzeppelin/test-helpers")
const { PERMIT_TYPEHASH, getPermitDigest, getDomainSeparator, sign } = require("./helpers/signature")

const WTOKEN = artifacts.require("CappedWrappedToken")

contract("::WTOKEN", async (accounts) => {
    let token
    const [alice, bob, carol, relayer] = accounts
    const name = "Wrapped Idexo Token" // token name
    let chainId // buidlerevm chain id
    // this key is from the first address on test evm
    const ownerPrivateKey = Buffer.from("01246b5dca23b6a21a3b0b59205bb57b8e5ffbe2204e2d76c67ea6459f505a51", "hex")

    describe("#Token", async () => {
        it("mint, burn", async () => {
            token = await WTOKEN.new("Wrapped Idexo Token", "WIDEXO", web3.utils.toWei(new BN(1000000)))
            await token.getChainId().then((res) => {
                chainId = res.toNumber()
            })
            await token.setRelayer(relayer)
            expectEvent(await token.mint(alice, web3.utils.toWei(new BN(100)), { from: relayer }), "Transfer")
            expectEvent(await token.burn(alice, web3.utils.toWei(new BN(100)), { from: relayer }), "Transfer")
            await token.balanceOf(alice).then((res) => {
                expect(res.toString()).to.eq("0")
            })
        })
        /*it('should permit and approve', async () => {
      // Create the approval request
      const approve = {
        owner: alice,
        spender: bob,
        value: 100,
      };
      // deadline as much as you want in the future
      const deadline = 100000000000000;
      // Get the user's nonce
      const nonce = await token.nonces(alice);
      // Get the EIP712 digest
      const digest = getPermitDigest(name, token.address, chainId, approve, nonce.toNumber(), deadline);
      // Sign it
      // NOTE: Using web3.eth.sign will hash the message internally again which
      // we do not want, so we're manually signing here
      const { v, r, s } = sign(digest, ownerPrivateKey);
      // Approve it
      expectEvent(
        await token.permit(approve.owner, approve.spender, approve.value, deadline, v, r, s),
        'Approval'
      );
    });*/
        describe("reverts if", async () => {
            it("non-owner call setRelayer", async () => {
                await expectRevert(token.setRelayer(bob, { from: bob }), "Ownable: caller is not the owner")
            })
            it("non-relayer call mint/burn", async () => {
                await expectRevert(token.mint(alice, web3.utils.toWei(new BN(100)), { from: bob }), "WTOKEN: CALLER_NO_RELAYER")
                await expectRevert(token.burn(alice, web3.utils.toWei(new BN(100)), { from: bob }), "WTOKEN: CALLER_NO_RELAYER")
            })
        })
    })
})
