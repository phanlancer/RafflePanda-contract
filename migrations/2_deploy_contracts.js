var Lottery = artifacts.require("./Lottery.sol");

module.exports = function(deployer) {
  deployer.deploy(web3.toWei(0.1, 'ether'), 100, {gas: 3000000});
};
