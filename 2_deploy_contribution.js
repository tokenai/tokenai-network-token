
var TokenAiContribution = artifacts.require("TokenAiContribution");
var MiniMeTokenFactory = artifacts.require("MiniMeTokenFactory");
var TAI = artifacts.require("TokenAiNetworkToken");


module.exports = function(deployer, network, accounts) {
  if (network.indexOf('dev') < -1) return // dont deploy on main net

  const TokenAiMs = '0x8416b276071d806240269b7f6a29960719db1c8f' //ms
  const giveth  = '0x5ADF43DD006c6C36506e2b2DFA352E60002d22Dc' //giveth
  const lawrence  = '0xa985c12cab14159abc12ecebb6c57d253d686ed6' //
  const sam  = '0x91cf44e67d638b498a55802f988662e395546388' //
  const ilana  = '0xaF919031D6c9597B005E260107E68054d5A2e0A8' //
  const seth  = '0x431f95797dff18f8686b3488e3e3629c10fd06e7' //
  const joseph  = '0x2Abd98a78d2533df345e0dEE5082D0c9b16E8985' //
//"0x8416b276071d806240269b7f6a29960719db1c8f","0x5ADF43DD006c6C36506e2b2DFA352E60002d22Dc","0xa985c12cab14159abc12ecebb6c57d253d686ed6","0x91cf44e67d638b498a55802f988662e395546388", "0xaF919031D6c9597B005E260107E68054d5A2e0A8","0x431f95797dff18f8686b3488e3e3629c10fd06e7","0x2Abd98a78d2533df345e0dEE5082D0c9b16E8985"
  deployer.deploy(MiniMeTokenFactory);
  deployer.deploy(TokenAiContribution,TokenAiMs,giveth,ilana,lawrence,sam,seth,joseph)
    .then(() => {
      return MiniMeTokenFactory.deployed()
        .then(f => {
          factory = f
          return TokenAiContribution.deployed( )
        })
        .then(c => {
          contribution = c
          return TAI.new(contribution.address,factory.address)
        }).then(t => {
          tai = t
          console.log('TAI: ', tai.address)
          contribution.setTokenAiNetworkToken(tai.address)
          return tai.totalSupply();
        }).then(totalSupply => {
          console.log('Deployed with a total supply of TAI @ ', totalSupply)
        });
    })
};
