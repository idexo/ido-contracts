const MultipleVotingMirror = artifacts.require('MultipleVotingMirror');
const StakePool = artifacts.require('StakePool');
const ERC20 = artifacts.require('ERC20Mock');

const { expect } = require('chai');
const { BN, expectRevert } = require('@openzeppelin/test-helpers');
const { toWei } = require('web3-utils');

contract('MultipleVotingMirror', async accounts => {
    let ido, erc20;
    let voting, sPool1, sPool2, sPool3;
    const [alice, bob, carol] = accounts;

    before(async () => {
        ido = await ERC20.new('Idexo Community', 'IDO');
        erc20 = await ERC20.new('USD Tether', 'USDT');
        sPool1 = await StakePool.new('Idexo Stake Token', 'IDS', ido.address, erc20.address);
        sPool2 = await StakePool.new('Idexo Stake Token', 'IDS', ido.address, erc20.address);
        sPool3 = await StakePool.new('Idexo Stake Token', 'IDS', ido.address, erc20.address);
        voting = await MultipleVotingMirror.new([sPool1.address, sPool2.address]);
        await voting.addOperator(bob);
    });

    describe('#Poll', async () => {
        before(async () => {
            await ido.mint(alice, toWei(new BN(10000000)));
            await ido.mint(bob, toWei(new BN(10000000)));
            await ido.approve(sPool1.address, toWei(new BN(10000000)));
            await ido.approve(sPool2.address, toWei(new BN(10000000)));
            await ido.approve(sPool1.address, toWei(new BN(10000000)), {from: bob});
            await ido.approve(sPool2.address, toWei(new BN(10000000)), {from: bob});
            await sPool1.deposit(toWei(new BN(4000)));
            await sPool1.deposit(toWei(new BN(7000)), {from: bob});
            await sPool2.deposit(toWei(new BN(8000)));
            await sPool2.deposit(toWei(new BN(14000)), {from: bob});
        });
        it('createPoll', async () => {
            await voting.createPoll('test', ['a', 'b'], new BN(1636299026), new BN(1636399026), new BN(0), {from: bob});
            await voting.getPollInfo(1).then(res => {
                expect(res[0]).to.eq('test');
            });
        });
        it('castVote valid', async () => {
            expect(await voting.checkIfVoted(1, bob)).to.eq(false);
            await voting.castVote(1, 2, {from: bob});
            expect(await voting.checkIfVoted(1, bob)).to.eq(true);
        });
        it('castVote invalid', async () => {
            expect(await voting.checkIfVoted(1, carol)).to.eq(false);
            await expectRevert(
                voting.castVote(1, 2, {from: carol}),
                'NO_VALID_VOTING_NFTS_PRESENT'
            );
        });
    });
});
