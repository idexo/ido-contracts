const {testStakePool} = require('./StakePool');

testStakePool('StakePool', 'StakePool', [5,1,10,1,15, 10,11,15]);
testStakePool('StakePoolMock', 'StakePoolMock', [1,0,0,0,0, 1,0,0.1]);
testStakePool('StakePoolMock1', 'StakePoolMock', [1,0,0,0,0, 1,0,0]);
