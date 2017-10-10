pragma solidity ^0.4.11;

/*
    Copyright 2017, Ilana Fraines TokenAi
    With heavy influence from District0xContribution.sol

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import "./SafeMath.sol";
import "./TokenAiNetworkToken.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./HasNoTokens.sol";
import "./interface/TokenController.sol";

contract TokenAiContribution is Pausable, HasNoTokens, TokenController {
    using SafeMath for uint;

    TokenAiNetworkToken public tokenAiNetworkToken;
    address public multisigWallet;                                      // Wallet that receives all sale funds
    address public givethWallet;                                        // Giveth team Wallet that receives all presale donation funds
    address public founder1;                                            // Wallet of founder 1
    address public founder2;                                            // Wallet of founder 2
    address public founder3;                                            // Wallet of founder 3
    address public founder4;                                            // Wallet of founder 4
    address[] public advisers;                                          // x Wallets of advisors

    uint public constant FOUNDER_STAKE = 10000 ether;                   //usd/eth
    uint public constant FOUNDER3_STAKE = 9000 ether;                    //usd/eth
    uint public constant FOUNDER4_STAKE = 3660 ether;                    //usd/eth
    uint public constant COMMUNITY_ADVISERS_STAKE = 3940 ether;         //usd/eth
    uint public constant CONTRIB_PERIOD1_STAKE = 145000 ether;          //usd/eth

    uint public minContribAmount = 0.01 ether;                          // 0.01 ether
    uint public maxGasPrice = 50000000000;                              // 50 GWei

    uint public constant TEAM_VESTING_CLIFF = 24 weeks;                 // 6 months vesting cliff for founders and advisors, except community advisors
    uint public constant TEAM_VESTING_PERIOD = 96 weeks;                // 2 years vesting period for founders and advisors, except community advisors

    bool public tokenTransfersEnabled = false;                          // TAI token transfers will be enabled manually
                                                                        // after contribution period
                                                                        // Can't be disabled back
    uint public initialPrice = 150;                                     // Number of TAI tokens for 1 eth, at the start of the sale
    uint public finalPrice = 120;                                       // Number of TAI tokens for 1 eth, at the end of the sale
    uint public bonusPrice = 100;                                       // Number of TAI tokens for 1 eth, in the 24hr bonus sale

    uint public priceStages = 4;                                        // Number of different price stages for interpolating between initialPrice and finalPrice
    uint public weiToEther = 1000000000000000000;                       // Number of wei in one ether

    struct Contributor {
        uint amount;                                                    // Amount of ETH contributed by an address in given contribution period
        uint price;                                                     // price qualified
        bool isCompensated;                                             // Whether this contributor received TAI token for ETH contribution
        uint amountCompensated;                                         // Amount of TAI received. Not really needed to store,
                                                                        // but stored for accounting and security purposes
    }

    uint public softCapAmount;                                          // Soft cap of contribution period in wei
    uint public afterSoftCapDuration;                                   // Number of seconds to the end of sale from the moment of reaching soft cap (unless reaching hardcap)
    uint public hardCapAmount;                                          // When reached this amount of wei, the contribution will end instantly
    uint public startTime;                                              // Start time of contribution period in UNIX time
    uint public endTime;                                                // End time of contribution period in UNIX time
    bool public isEnabled;                                              // If contribution period was enabled by multisignature
    bool public softCapReached;                                         // If soft cap was reached
    bool public hardCapReached;                                         // If hard cap was reached
    uint public totalContributed;                                       // Total amount of ETH contributed in given period
    address[] public contributorsKeys;                                  // Addresses of all contributors in given contribution period
    mapping (address => Contributor) public contributors;

    event onContribution(uint totalContributed, address indexed contributor, uint amount,
        uint contributorsCount);
    event onSoftCapReached(uint endTime);
    event onHardCapReached(uint endTime);
    event onCompensated(address indexed contributor, uint amount);
    event onPresaleContribution(address indexed contributor, uint amount, uint price);

    modifier onlyMultisig() {
        require(multisigWallet == msg.sender);
        _;
    }

    modifier nonZeroAddress(address x) {
        require (x != 0);
        _;
    }

    modifier onlyBeforeSale {
      require (now < startTime && !isEnabled );
      _;
    }

    function TokenAiContribution(
        address _multisigWallet,
        address _givethWallet,
        address _founder1,
        address _founder2,
        address _founder3,
        address _founder4,
        address[] _advisers
    ) {
        //require(_advisers.length == 5);
        multisigWallet = _multisigWallet;
        givethWallet = _givethWallet;
        founder1 = _founder1;
        founder2 = _founder2;
        founder3 = _founder3;
        founder4 = _founder4;
        advisers = _advisers;
    }

    // @notice Returns true if contribution period is currently running
    function isContribPeriodRunning() constant returns (bool) {
        return !hardCapReached &&
               isEnabled &&
               startTime <= now &&
               endTime > now;
    }

    function contribute()
        payable
        stopInEmergency
    {
        contributeWithAddress(msg.sender);
    }

    // @notice Function to participate in contribution period
    // Amounts from the same address should be added up
    // If soft or hard cap is reached, end time should be modified
    // Funds should be transferred into multisig wallet
    // @param contributor Address that will receive TAI token
    function contributeWithAddress(address contributor)
        payable
        stopInEmergency
    {
        require(tx.gasprice <= maxGasPrice);
        require(msg.value >= minContribAmount);
        if(isContribPeriodRunning()){
          uint contribValue = msg.value;
          uint excessContribValue = 0;

          uint oldTotalContributed = totalContributed;

          totalContributed = oldTotalContributed.add(contribValue);

          uint newTotalContributed = totalContributed;

          // Soft cap was reached
          if (newTotalContributed >= softCapAmount &&
              oldTotalContributed < softCapAmount)
          {
              softCapReached = true;
              endTime = afterSoftCapDuration.add(now);
              onSoftCapReached(endTime);
          }
          // Hard cap was reached
          if (newTotalContributed >= hardCapAmount &&
              oldTotalContributed < hardCapAmount)
          {
              hardCapReached = true;
              endTime = now;
              onHardCapReached(endTime);

              // Everything above hard cap will be sent back to contributor
              excessContribValue = newTotalContributed.sub(hardCapAmount);
              contribValue = contribValue.sub(excessContribValue);

              totalContributed = hardCapAmount;
          }

          if (contributors[contributor].amount == 0) {
              contributorsKeys.push(contributor);
          }
          contributors[contributor].price = getPrice(now);
          contributors[contributor].amount = contributors[contributor].amount.add(contribValue);
          //transfer contrution to multisigWallet
          multisigWallet.transfer(contribValue);
          if (excessContribValue > 0) {
              msg.sender.transfer(excessContribValue);
          }
          onContribution(newTotalContributed, contributor, contribValue, contributorsKeys.length);
        } else{
          if (contributors[contributor].amount == 0) {
              contributorsKeys.push(contributor);
          }
          contributors[contributor].price = 1;
          contributors[contributor].amount = contributors[contributor].amount.add(contribValue);

          //transfer contrution to giveth wallet if user tries to contribut in advance of sale
          givethWallet.transfer(contribValue);
        }
    }

    // @notice This method is called by owner after contribution period ends, to distribute TAI based on the stage of purchase and price
    // Each contributor should receive TAI just once even if this method is called multiple times
    // In case of many contributors must be able to compensate contributors in paginational way, otherwise might
    // run out of gas if wanted to compensate all on one method call. Therefore parameters offset and limit
    // @param offset Number of first contributors to skip.
    // @param limit Max number of contributors compensated on this call
    function compensateContributors(uint offset, uint limit)
        onlyOwner
    {
        require(isEnabled);
        require(endTime < now);

        uint i = offset;
        uint compensatedCount = 0;
        uint contributorsCount = contributorsKeys.length;

        while (i < contributorsCount && compensatedCount < limit) {
            address contributorAddress = contributorsKeys[i];
            if (!contributors[contributorAddress].isCompensated) {
                uint amountEther = SafeMath.div(contributors[contributorAddress].amount,weiToEther);
                uint contributionPrice = contributors[contributorAddress].price;
                uint tokensGranted = SafeMath.mul(amountEther, contributionPrice); //  Calculate how many tokens bought
                contributors[contributorAddress].amountCompensated = tokensGranted;

                tokenAiNetworkToken.transfer(contributorAddress, contributors[contributorAddress].amountCompensated);
                contributors[contributorAddress].isCompensated = true;
                onCompensated(contributorAddress, contributors[contributorAddress].amountCompensated);

                compensatedCount++;
            }
            i++;
        }
    }

    // @notice TokenAi needs to make initial token allocations for presale partners
    // This allocation has to be made before the sale is activated. Activating the sale means no more
    // arbitrary allocations are possible and expresses conformity.
    // @param contributor: The contributors address.
    // @param weiAmount: Amount of wei contributed.
    // @param taiPerEth: taiPerEth of TAI per eth.
    function allocatePresaleTokens(address contributor, uint weiAmount, uint taiPerEth)
             onlyBeforeSale
             nonZeroAddress(contributor)
             onlyMultisig
             public {

      uint oldTotalContributed = totalContributed;

      totalContributed = oldTotalContributed.add(weiAmount);

      uint newTotalContributed = totalContributed;

        // Soft cap was reached
        if (newTotalContributed >= softCapAmount &&
                   oldTotalContributed < softCapAmount)
        {
            softCapReached = true;
            endTime = afterSoftCapDuration.add(now);
            onSoftCapReached(endTime);
        }

        if (contributors[contributor].amount == 0) {
            contributorsKeys.push(contributor);
        }
        contributors[contributor].price = taiPerEth;
        contributors[contributor].amount = contributors[contributor].amount.add(weiAmount);
        onPresaleContribution(contributor, weiAmount, taiPerEth);
    }

    // @notice Gets what the price is for a given stage
    // @param stage: Stage number
    // @return price per eth for that stage.
    // If sale stage doesn't exist, returns 0.
    function priceForStage(uint8 stage) constant internal returns (uint256) {
        if (stage >= priceStages) return 0;
        uint priceDifference = SafeMath.sub(initialPrice, finalPrice);
        uint stageDelta = SafeMath.div(priceDifference, uint(priceStages - 1));
        return SafeMath.sub(initialPrice, SafeMath.mul(uint256(stage), stageDelta));
    }
    // @notice Gets what the stage is for a given date and time
    // @param datetime: UNIX time
    // @return The sale stage for that date time. Stage is between 0 and (priceStages - 1)
    function stageForDate(uint dateTime) constant internal returns (uint8) {
        uint current = SafeMath.sub(dateTime, startTime);
        uint totalTime = SafeMath.sub(endTime, startTime);

        return uint8(SafeMath.div(SafeMath.mul(priceStages, current), totalTime));
    }

    // @notice Get the price for a TAI token at any given date
    // @param dateTime for which the price is requested
    // @return Number of eth-TAI for 1 eth
    // If sale isn't ongoing for that time, returns 0. Last 24hrs bonus period price
    function getPrice(uint dateTime) constant public returns (uint256) {
      if (dateTime < startTime || dateTime >= endTime) return 0;
        if(dateTime > SafeMath.sub(endTime,86400)){
          return bonusPrice;
        } else{
          return priceForStage(stageForDate(dateTime));
        }
      }

    // @notice Method for setting up contribution period
    // Only owner should be able to execute
    // Setting first contribution period sets up vesting for founders & advisors
    // Contribution period should still not be enabled after calling this method
    // @param softCapAmount Soft Cap in eth
    // @param afterSoftCapDuration Number of seconds till the end of sale in the moment of reaching soft cap (unless reaching hard cap)
    // @param hardCapAmount Hard Cap in eth
    // @param startTime Contribution start time in UNIX time
    // @param endTime Contribution end time in UNIX time
    function setContribPeriod(
        uint _softCapAmount,
        uint _afterSoftCapDuration,
        uint _hardCapAmount,
        uint _startTime,
        uint _endTime
    )
        onlyOwner
    {
        require(_softCapAmount > 0);
        require(_hardCapAmount > _softCapAmount);
        require(_afterSoftCapDuration > 0);
        require(_startTime > now);
        require(_endTime > _startTime);
        require(!isEnabled);

        softCapAmount = _softCapAmount;
        afterSoftCapDuration = _afterSoftCapDuration;
        hardCapAmount = _hardCapAmount;
        startTime = _startTime;
        endTime = _endTime;

       tokenAiNetworkToken.revokeAllTokenGrants(founder1);
       tokenAiNetworkToken.revokeAllTokenGrants(founder2);
       tokenAiNetworkToken.revokeAllTokenGrants(founder3);
       tokenAiNetworkToken.revokeAllTokenGrants(founder4);

        for (uint j = 0; j < advisers.length; j++) {
            tokenAiNetworkToken.revokeAllTokenGrants(advisers[j]);
        }

         uint64 vestingDate = uint64(startTime.add(TEAM_VESTING_PERIOD));
         uint64 cliffDate = uint64(startTime.add(TEAM_VESTING_CLIFF));
         uint64 startDate = uint64(startTime);

        tokenAiNetworkToken.grantVestedTokens(founder1, FOUNDER_STAKE, startDate, cliffDate, vestingDate, true, false);
        tokenAiNetworkToken.grantVestedTokens(founder2, FOUNDER_STAKE, startDate, cliffDate, vestingDate, true, false);
        tokenAiNetworkToken.grantVestedTokens(founder3, FOUNDER3_STAKE, startDate, cliffDate, vestingDate, true, false);
        tokenAiNetworkToken.grantVestedTokens(founder4, FOUNDER4_STAKE, startDate, cliffDate, vestingDate, true, false);

        // Community advisors stake has no vesting, but we set it up this way, so we can revoke it in case of
        // re-setting up contribution period
        tokenAiNetworkToken.grantVestedTokens(advisers[4], COMMUNITY_ADVISERS_STAKE, startDate, startDate, startDate, true, false);
    }

    // @notice Enables contribution period
    // Must be executed by multisignature
    function enableContribPeriod()
        onlyMultisig
    {
        require(startTime > now);
        isEnabled = true;
    }

    // @notice Sets new min. contribution amount
    // Only owner can execute
    // Cannot be executed while contribution period is running
    // @param _minContribAmount new min. amount
    function setMinContribAmount(uint _minContribAmount)
        onlyOwner
    {
        require(_minContribAmount > 0);
        require(startTime > now);
        minContribAmount = _minContribAmount;
    }

    // @notice Sets new max gas price for contribution
    // Only owner can execute
    // Cannot be executed while contribution period is running
    // @param _minContribAmount new min. amount
    function setMaxGasPrice(uint _maxGasPrice)
        onlyOwner
    {
        require(_maxGasPrice > 0);
        require(startTime > now);
        maxGasPrice = _maxGasPrice;
    }

    // @notice Sets TokenAiNetworkToken contract
    // Generates all TAI tokens and assigns them to this contract
    // If token contract has already generated tokens, do not generate again
    // @param _tokenAiNetworkToken TokenAiNetworkToken address
    function setTokenAiNetworkToken(address _tokenAiNetworkToken)
        onlyOwner
    {
        require(_tokenAiNetworkToken != 0);
        require(!isEnabled);
        tokenAiNetworkToken = TokenAiNetworkToken(_tokenAiNetworkToken);
        if (tokenAiNetworkToken.totalSupply() == 0) {
            tokenAiNetworkToken.generateTokens(this, FOUNDER_STAKE
              .add(FOUNDER_STAKE)
              .add(FOUNDER3_STAKE)
              .add(FOUNDER4_STAKE)
              .add(COMMUNITY_ADVISERS_STAKE)
              .add(CONTRIB_PERIOD1_STAKE));

        }
    }

    // @notice Enables transfers of TAI
    // Will be executed after first contribution period by owner
    function enableTokenAiTransfers()
        onlyOwner
    {
        require(endTime < now);
        tokenTransfersEnabled = true;
    }

    // @notice Method to claim tokens accidentally sent to a TAI contract
    // Only multisig wallet can execute
    // @param _token Address of claimed ERC20 Token
    function claimTokensFromTokenAiNetworkToken(address _token)
        onlyMultisig
    {
        tokenAiNetworkToken.claimTokens(_token, multisigWallet);
    }

    // @notice Kill method should not really be needed, but just in case
    function kill(address _to) onlyMultisig external {
        suicide(_to);
    }

    function()
        payable
        stopInEmergency
    {
        contributeWithAddress(msg.sender);
    }

    // MiniMe Controller default settings for allowing token transfers.
    function proxyPayment(address _owner) payable public returns (bool) {
        revert();
    }

    // Before transfers are enabled for everyone, only this contract is allowed to distribute TAI
    function onTransfer(address _from, address _to, uint _amount) public returns (bool) {
        return tokenTransfersEnabled || _from == address(this) || _to == address(this);
    }

    function onApprove(address _owner, address _spender, uint _amount) public returns (bool) {
        return tokenTransfersEnabled;
    }

    function isTokenSaleToken(address tokenAddr) returns(bool) {
        return tokenAiNetworkToken == tokenAddr;
    }

    /*
     Following constant methods are used for tests and contribution web app
     They don't impact logic of contribution contract, therefor DOES NOT NEED TO BE AUDITED
     */

    // Used by contribution front-end to obtain contribution period properties
    function getContribPeriod()
        constant
        returns (bool[3] boolValues, uint[8] uintValues)
    {
        boolValues[0] = isEnabled;
        boolValues[1] = softCapReached;
        boolValues[2] = hardCapReached;

        uintValues[0] = softCapAmount;
        uintValues[1] = afterSoftCapDuration;
        uintValues[2] = hardCapAmount;
        uintValues[3] = startTime;
        uintValues[4] = endTime;
        uintValues[5] = totalContributed;
        uintValues[6] = contributorsKeys.length;
        uintValues[7] = CONTRIB_PERIOD1_STAKE;

        return (boolValues, uintValues);
    }

    // Used by contribution front-end to obtain contribution contract properties
    function getConfiguration()
        constant
        returns (bool, address, address, address, address, address, address[] _advisers, bool, uint)
    {
        _advisers = new address[](advisers.length);
        for (uint i = 0; i < advisers.length; i++) {
            _advisers[i] = advisers[i];
        }
        return (stopped, multisigWallet, founder1, founder2, founder3, founder4, _advisers, tokenTransfersEnabled,
            maxGasPrice);
    }

    // Used by contribution front-end to obtain contributor's properties
    function getContributor(address contributorAddress)
        constant
        returns(uint, bool, uint, uint)
    {
        Contributor contributor = contributors[contributorAddress];
        return (contributor.amount, contributor.isCompensated, contributor.amountCompensated , contributor.price);
    }

    // Function to verify if all contributors were compensated
    function getUncompensatedContributors(uint offset, uint limit)
        constant
        returns (uint[] contributorIndexes)
    {
        uint contributorsCount = contributorsKeys.length;

        if (limit == 0) {
            limit = contributorsCount;
        }

        uint i = offset;
        uint resultsCount = 0;
        uint[] memory _contributorIndexes = new uint[](limit);

        while (i < contributorsCount && resultsCount < limit) {
            if (!contributors[contributorsKeys[i]].isCompensated) {
                _contributorIndexes[resultsCount] = i;
                resultsCount++;
            }
            i++;
        }

        contributorIndexes = new uint[](resultsCount);
        for (i = 0; i < resultsCount; i++) {
            contributorIndexes[i] = _contributorIndexes[i];
        }
        return contributorIndexes;
    }

    function getNow() constant returns(uint)
    {
        return now;
    }

}
