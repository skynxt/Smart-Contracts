pragma solidity ^0.4.10;
//
contract Assert {

  function assert(bool assert) internal {
      if (!assert) { throw; }
  }

}

//Buffer overflow implementation
contract Math is Assert {

    function safeMul(uint a, uint b) internal returns (uint) {
        uint c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }

    function safeSub(uint a, uint b) internal returns (uint) {
        assert(b <= a);
        return a - b;
    }

    function safeAdd(uint a, uint b) internal returns (uint) {
        uint c = a + b;
        assert(b <= c && c >= a);
        return c;
    }

}

//Utility contract for time windowed distribution of tokens
contract Tranche is Math {
    
    //initialize the function with the total number of tranches
    function Tranche(uint tr) { 
        totalTranches = tr;
        uint totalTime = safeSub(endTime, startTime);
        timeWindow =  totalTime / totalTranches;
        tokenTranche = totalSupply / totalTranches;
    }

    function tokenSupply() returns (uint) { return totalSupply; } //returns total supply of tokens 
    function start() returns (uint) { return startTime; } //start time of distribution of tokens
    function end() returns (uint) { return endTime; } //end time of distribution of tokens
    function trancheWindow() returns (uint) { return timeWindow; } //time window during which slice of total tokens are distributed
    function tokensPerTranch() returns (uint) { return tokenTranche; } //MAX slice of total tokens that can be distributed during a time window
    function tranches() returns (uint) { return totalTranches; } //total number of batches, during each batch a slice of total tokens are distributed

    uint constant totalSupply = 5000000; // Total supply of tokens
    uint constant private startTime = 1491280000; //UNIX timestamp, start time of token distribution
    uint constant private endTime = 1491480000; //end time ~2 days after start date
    uint private timeWindow; //time interval in seconds
    uint private tokenTranche; //per tranche these many tokens to be sold
    uint private totalTranches;
}

//ERC20 standard, standard protocol for Ethereum based tokens 
// more https://github.com/ethereum/EIPs/issues/20
contract ERC20 {

    function transfer(address to, uint256 value) returns (bool success) {
        if (tokenOwned[msg.sender] >= value && tokenOwned[to] + value > tokenOwned[to]) {
            tokenOwned[msg.sender] -= value;
            tokenOwned[to] += value;
            Transfer(msg.sender, to, value);
            return true;
        } else { return false; }
    }

    function transferFrom(address from, address to, uint256 value) returns (bool success) {
        if (tokenOwned[from] >= value && allowed[from][msg.sender] >= value && tokenOwned[to] + value > tokenOwned[to]) {
            tokenOwned[to] += value;
            tokenOwned[from] -= value;
            allowed[from][msg.sender] -= value;
            Transfer(from, to, value);
            return true;
        } else { return false; }
    }

    function balanceOf(address owner) constant returns (uint256 balance) {
        return tokenOwned[owner];
    }

    function approve(address spender, uint256 value) returns (bool success) {
        allowed[msg.sender][spender] = value;
        Approval(msg.sender, spender, value);
        return true;
    }

    function allowance(address owner, address spender) constant returns (uint256 remaining) {
        return allowed[owner][spender];
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    mapping(address => uint) internal tokenOwned; // Contract field for storing token balance owned by certain address

    mapping (address => mapping (address => uint256)) allowed;

    uint256 public totalSupply;

}

//TokenDistibution contract inherits Math, ERC20 contracts, this class instatntiates the token distribution process
//This contract implements time windowed distribution of tokens, during each time window a slice of total token is distributed based on the demand
//Once the uppercap of the slice of total tokens is reached, the contract no longer distributes the token until the next time window and so on...
contract TokenDistibution is Math, ERC20 {
    
    //assigns owner to the contract & initilizes the number of tranches
    function TokenDistibution() {
        owner = msg.sender;
        tranche = new Tranche(10); // intialize with 10 total tranches for between start to end time
    }

    //throw on user tries to buy tokes after the end time
    modifier is_later_than() {
        assert(tranche.end() > now);
        _;
    }
    
    //Demand calculation function, where more the number of token requested by the user, lesser the price for each token
    function demandCalc(uint amt) returns (uint){
        if(amt > DEMAND2 && amt <= DEMAND1) {
            return PRICE3;
        }
        else if(amt > DEMAND3 && amt <= DEMAND2) {
            return PRICE2;
        }
        else if(amt > 0 && amt <= DEMAND3) {
            return PRICE1;
        }
        assert(false);
    }
    
    //initiate the buy quoting the amount intended to buy
    // buy succeeds only when its is initiated within the time window, during which a slice of tokens is allocated out of total supply proportiante to the amount requestd bsaed on demand
    function buy(uint amt) 
        payable 
        is_later_than
        returns (bool) {
        if(amt > 0 && msg.value > 0) {
            uint totalCompletionOfTranches = ((now - tranche.start()) / tranche.trancheWindow()) + 1; // total number of tranches completed since start            
            uint tokensAllocatedForTranche = safeSub(safeMul(totalCompletionOfTranches, tranche.tokensPerTranch()), tokensIssued);
            uint tokensMinted = safeMul(demandCalc(amt), msg.value);
            uint tokensToBeIssued = safeAdd(tokensIssued, tokensMinted);
            if(tokensAllocatedForTranche > 0 
                    && tokensMinted <= tokensAllocatedForTranche 
                    && tokensToBeIssued <= tranche.tokenSupply()) {
                tokensIssued = tokensToBeIssued;
                tokenOwned[msg.sender] = tokensMinted;
                etherSent[msg.sender] = msg.value;
                return true;
            }
        }
        assert(false);
    }

    //owner of the contract will be able to redeem unsold tokens once token sale has ended    
    function recoverUnclaimedTokens() {
        if(now > tranche.end() && owner == msg.sender) {
            tokenOwned[owner] = safeSub(tranche.tokenSupply(), tokensIssued);
        }
    }

    address owner;
    Tranche internal tranche;
    uint internal tokensIssued = 0;
    
    mapping (address => uint) internal etherSent; // Contract field for storing how much Ether was sent from certain address
    
    uint public constant DEMAND1 = 200;
    uint public constant DEMAND2 = 100;
    uint public constant DEMAND3 = 50;
    
    uint public constant PRICE1 = 5; //200=>5
    uint public constant PRICE2 = 3; //100=>3
    uint public constant PRICE3 = 1; //50=>1
}
