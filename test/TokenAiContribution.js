// Zeppelin tests for ERC20 StandardToken.

var TokenAiContribution = artifacts.require("TokenAiContribution.sol");
var StandardToken = artifacts.require("TokenAiNetworkToken.sol");
var MiniMeTokenFactory = artifacts.require("MiniMeTokenFactory.sol");

const increaseTime = addSeconds => {
    web3.currentProvider.send({
        jsonrpc: "2.0",
        method: "evm_increaseTime",
        params: [addSeconds],
        id: 0
    })
}
const mineBlock = mine => {
    web3.currentProvider.send({
        jsonrpc: "2.0",
        method: "evm_mine",
        id: 12345
    })
}

contract('TokenAIContributionContract', function(accounts) {
  let token;
  let contributionContract;
  let now;

    beforeEach(async () => {
      const minime = await MiniMeTokenFactory.new();
      contributionContract = await TokenAiContribution.new(accounts[5],accounts[4],accounts[0],accounts[1],accounts[2],accounts[3],accounts[6]);
      const tokenDeploy = await StandardToken.new(contributionContract.address, minime.address);
      await contributionContract.setTokenAiNetworkToken(tokenDeploy.address);
      token = StandardToken.at(await contributionContract.tokenAiNetworkToken());
      now = web3.eth.getBlock(web3.eth.blockNumber).timestamp;

  });

  it("should mint correct token supply", async function() {
    await contributionContract.setContribPeriod("170000000000000000000000", 3600,"185000000000000000000000", now + 3600, now+ 7200);
    let totalSupply = await token.totalSupply();
    assert.equal(totalSupply, 33935250000000000000000000);
  });

  it("should grant tokens for founders ", async function() {
    await contributionContract.setContribPeriod("250000000000000000000000", 3600,"300000000000000000000000", now + 3600, now+ 7200);

    let founder1 = await token.balanceOf(accounts[0]);
    let founder2 = await token.balanceOf(accounts[1]);
    let founder3 = await token.balanceOf(accounts[2]);
    let founder4 = await token.balanceOf(accounts[3]);
    let founder5 = await token.balanceOf(accounts[6]);

    assert.equal(await token.tokenGrantsCount(accounts[0]),1);
    assert.equal(await token.tokenGrantsCount(accounts[1]),1);
    assert.equal(await token.tokenGrantsCount(accounts[2]),1);
    assert.equal(await token.tokenGrantsCount(accounts[3]),1);
    assert.equal(await token.tokenGrantsCount(accounts[6]),1);

    assert.equal(founder1, 1650000000000000000000000);
    assert.equal(founder2, 1650000000000000000000000);
    assert.equal(founder3, 1375050000000000000000000);
    assert.equal(founder4, 550050000000000000000000);
    assert.equal(founder5, 550050000000000000000000);
  });

  it("should allow contribution only after isEnabled function call", async function() {
    await contributionContract.setContribPeriod("170000000000000000000000", 30,"185000000000000000000000", now + 3600, now+ 7200);
    assert.equal(await contributionContract.isEnabled(), false);

    let tx = await contributionContract.enableContribPeriod();
    assert.equal(await contributionContract.isEnabled(), true);
  });

  it("should send ether to Giveth before contribution period", async function() {

    await contributionContract.setContribPeriod("170000000000000000000000", 3600,"185000000000000000000000", now + 3600, now+ 7200);

    let givethWalletOriginalBalance = await web3.eth.getBalance(accounts[4]);
    let tx3 = await web3.eth.sendTransaction({from:accounts[7], to: contributionContract.address, value: web3.toWei(2,'ether'), gas: 500000});

    await increaseTime(7208);
    await mineBlock();

    let newBalance1 = await web3.eth.getBalance(accounts[4]);

    assert.equal(newBalance1,  +givethWalletOriginalBalance + +(web3.toWei(2,'ether')));
  });

  it("should allow contributions if contribution period is enabled and startTime reached", async function() {

    await contributionContract.setContribPeriod("170000000000000000000000", 30,"185000000000000000000000", now + 3600, now+ 7200);
    let tx = await contributionContract.enableContribPeriod();

    await increaseTime(3601);
    await mineBlock();

    let newNow = web3.eth.getBlock(web3.eth.blockNumber).timestamp;
    let originalBalance = await web3.eth.getBalance(accounts[5]);

    let tx2 = await web3.eth.sendTransaction({from:accounts[7], to: contributionContract.address, value: web3.toWei(2,'ether'), gas: 500000});
    await increaseTime(2);
    await mineBlock();

    let newBalance = await web3.eth.getBalance(accounts[5]);

    assert.equal(newBalance,  +originalBalance + +(web3.toWei(2,'ether')));

   });

   it("should revert transaction if contributing period is over", async function() {

     await contributionContract.setContribPeriod("170000000000000000000000", 30,"185000000000000000000000", now + 3600, now+ 7200);
     await contributionContract.enableContribPeriod();

     await increaseTime(7201);
     await mineBlock();

     let originalBalance1 = await web3.eth.getBalance(accounts[5]);
     let givethWalletOriginalBalance = await web3.eth.getBalance(accounts[4]);

     await web3.eth.sendTransaction({from:accounts[7], to: contributionContract.address, value: web3.toWei(2,'ether'), gas: 500000});
     await increaseTime(2);
     await mineBlock();

     let newBalance2 = await web3.eth.getBalance(accounts[5]);
     let newBalance2giveth = await web3.eth.getBalance(accounts[4]);

     assert.equal(newBalance2,  +originalBalance1);
     assert.equal(newBalance2giveth,  +givethWalletOriginalBalance);

   });

   it("should accomodate presale contributor before start of sale", async function() {

     await contributionContract.setContribPeriod("170000000000000000000000", 30,"185000000000000000000000", now + 3600, now+ 7200);
     await increaseTime(10);
     await mineBlock();

     await contributionContract.allocatePresaleTokens("0xaF919031D6c9597B005E260107E68054d5A2e0A8", "1000000000000000000", 150);
     await contributionContract.enableContribPeriod();

     await increaseTime(7201);
     await mineBlock();

     await contributionContract.compensateContributors(0,10);
     await contributionContract.getContributor("0xaF919031D6c9597B005E260107E68054d5A2e0A8");

     assert.equal(150000000000000000000 , await token.balanceOf("0xaF919031D6c9597B005E260107E68054d5A2e0A8"));

   });

   it("should accept contributions and mint tokens at correct price", async function() {

     await contributionContract.setContribPeriod("170000000000000000000000", 30,"185000000000000000000000", now + 3600, now+ 7200);
     await contributionContract.enableContribPeriod();

     await increaseTime(3601);
     await mineBlock();
     await web3.eth.sendTransaction({from:accounts[7], to: contributionContract.address, value: web3.toWei(2,'ether'), gas: 500000});

     await increaseTime(1202);
     await mineBlock();
     await web3.eth.sendTransaction({from:accounts[7], to: contributionContract.address, value: web3.toWei(1,'ether'), gas: 500000});

     await increaseTime(5000);
     await mineBlock();
     await contributionContract.compensateContributors(0,10);

     assert.equal(440000000000000000000 , await token.balanceOf(accounts[7]));

   });

   it("should allocate correct token amount in bonus sale", async function() {

     await contributionContract.setContribPeriod("170000000000000000000000", 30,"185000000000000000000000", now + 3600, now+ 7200);
     await contributionContract.enableContribPeriod();

     await increaseTime(7190);
     await mineBlock();
     await web3.eth.sendTransaction({from:accounts[7], to: contributionContract.address, value: web3.toWei(1,'ether'), gas: 500000});
     await increaseTime(7200);
     await mineBlock();
     await contributionContract.compensateContributors(0,10);
     assert.equal(100000000000000000000 , await token.balanceOf(accounts[7]));
   })

   it("should give correct token price for all price stages", async function() {

     await contributionContract.setContribPeriod("170000000000000000000000", 30,"185000000000000000000000", now + 3600, now + 7200);
     await increaseTime(3601);
     await mineBlock();

     assert.equal(150,parseInt( await contributionContract.getPrice(web3.eth.getBlock(web3.eth.blockNumber).timestamp)));

     await increaseTime(1202);
     await mineBlock();

     assert.equal(140 ,parseInt( await contributionContract.getPrice(web3.eth.getBlock(web3.eth.blockNumber).timestamp)));

     await increaseTime(1202);
     await mineBlock();

     assert.equal(130 , parseInt(await contributionContract.getPrice(web3.eth.getBlock(web3.eth.blockNumber).timestamp)));

     await increaseTime(1000);
     await mineBlock();

     assert.equal(120 , parseInt(await contributionContract.getPrice(web3.eth.getBlock(web3.eth.blockNumber).timestamp)));

     await increaseTime(190);
     await mineBlock();

     assert.equal(100 , parseInt(await contributionContract.getPrice(web3.eth.getBlock(web3.eth.blockNumber).timestamp)));

     await increaseTime(90);
     await mineBlock();

     assert.equal(0 , parseInt(await contributionContract.getPrice(web3.eth.getBlock(web3.eth.blockNumber).timestamp)));

   })

   it("should stop taking contributions when hard cap is reached", async function() {

     await contributionContract.setContribPeriod("170000000000000000000", 30,"185000000000000000000", now + 3600, now+ 7200);
     await contributionContract.enableContribPeriod();

     await increaseTime(4802);
     await mineBlock();

     await web3.eth.sendTransaction({from:accounts[7], to: contributionContract.address, value: "186000000000000000001", gas: 500000});
     await increaseTime(7200);
     await mineBlock();
     await contributionContract.compensateContributors(0,10);

     assert.equal(25900000000000000000000 , await token.balanceOf(accounts[7]));
   })

   it("should not accept more than softcap in presale", async function() {

     await contributionContract.setContribPeriod("170000000000000000000000", 30,"185000000000000000000000", now + 3600, now+ 7200);
     await increaseTime(10);
     await mineBlock();

     await contributionContract.allocatePresaleTokens("0xaF919031D6c9597B005E260107E68054d5A2e0A8", "180000000000000000000000", 160);
     await contributionContract.enableContribPeriod();

     await increaseTime(7800);
     await mineBlock();

     await contributionContract.compensateContributors(0,10);

     assert.equal(27200000000000000000000000 , await token.balanceOf("0xaF919031D6c9597B005E260107E68054d5A2e0A8"));

   })
   it("should burn remaining tokens after contribution event", async function() {
     await contributionContract.setContribPeriod("170000000000000000000000", 30,"185000000000000000000000", now + 3600, now+ 7200);
     await increaseTime(10);
     await mineBlock();

     await contributionContract.allocatePresaleTokens("0xaF919031D6c9597B005E260107E68054d5A2e0A8", "36000000000000000000", 160);
     await contributionContract.enableContribPeriod();

     await increaseTime(7800);
     await mineBlock();

     await contributionContract.compensateContributors(0,10);

     let totalSupplyBefore = await token.totalSupply();
     assert.equal(totalSupplyBefore, 33935250000000000000000000);

     let contractSupplyBefore = await token.balanceOf(contributionContract.address);
     assert.equal(contractSupplyBefore, 27494340000000000000000000);

     await contributionContract.finalizeContributionEvent();
     let contractSupply = await token.balanceOf(contributionContract.address);
     assert.equal(web3.fromWei(contractSupply, "ether" ).toNumber(), 0);

     let totalSupplyAfter = await token.totalSupply();
     let totalSupplyAfterVal = 33935250000000000000000000 - 27494340000000000000000000;
     assert.equal(parseInt(totalSupplyAfter),parseInt(totalSupplyAfterVal));
   });

   it("should not accept funds after endTime", async function() {
     await contributionContract.setContribPeriod("170000000000000000000000", 30,"185000000000000000000000", now + 3600, now+ 7200);
     await increaseTime(10);
     await mineBlock();

     await contributionContract.enableContribPeriod();

     await increaseTime(7800);
     await mineBlock();
     try {
       let transfer =  await web3.eth.sendTransaction({from:accounts[7], to: contributionContract.address, value: "18600000000000000000", gas: 500000});
     } catch(e) {
       assert.equal("VM Exception while processing transaction: invalid opcode",e.message);
     }

   });

  it("should only allow transfers when token transfers are enabled", async function() {

    await contributionContract.setContribPeriod("170000000000000000000000", 30,"185000000000000000000000", now + 3600, now+ 7200);
    await contributionContract.enableContribPeriod();

    await increaseTime(7000);
    await mineBlock();
    await web3.eth.sendTransaction({from:accounts[7], to: contributionContract.address, value: "1000000000000000000", gas: 500000});

    await increaseTime(7800);
    await mineBlock();
    await contributionContract.compensateContributors(0,10);

    try {
      let transfer = await token.transfer(accounts[7], 100);
    } catch(e) {
      assert.equal("VM Exception while processing transaction: invalid opcode",e.message);
    }
    await contributionContract.enableTokenAiTransfers();

    let transfer = await token.transfer(accounts[7], 100);
    assert.equal(120000000000000000000, parseInt(await token.balanceOf(accounts[7])));

    });
});
