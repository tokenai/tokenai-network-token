pragma solidity ^0.4.14;

import "./MiniMeToken.sol";
import "./VestedToken.sol";

contract TokenAiNetworkToken is MiniMeToken, VestedToken {
    function TokenAiNetworkToken(address _controller, address _tokenFactory)
        MiniMeToken(
            _tokenFactory,
            0x0,                        // no parent token
            0,                          // no snapshot block number from parent
<<<<<<< HEAD
            "TokenAI Netwok Token",     // Token name
=======
            "TokenAi Netwok Token",     // Token name
>>>>>>> 70baa688f6bb5cc188305809824141aad3c87b0e
            18,                         // Decimals
            "TAI",                      // Symbol
            true                        // Enable transfers
            )
    {
        changeController(_controller);
    }
}
