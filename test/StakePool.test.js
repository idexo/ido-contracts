const {testStakePool} = require('./StakePool');

testStakePool('StakePool', 'StakePool', [5,1,10,1,15, 10,11,15]);
testStakePool('StakePoolMock', 'StakePoolMock', [0,0,0,0,0, 0,0,0]);
testStakePool('StakePoolMock1', 'StakePoolMock', [0,0,0,0,0, 0,0,0]);
