// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract BrewSmartContractTest {
    BrewBank public brew_bank;
    address public account_address;
    
    function CreateBrewBank() public {
        brew_bank = new BrewBank(300, 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4);
        
        brew_bank.AddInvestmentStrategy("CURVE_AAVE_STABLE_SWAP", address(new CurveAaveDaiInvestableAccount()));
        brew_bank.AddInvestmentStrategy("CURVE_AAVE_STABLE_SWAP_WITH_REWARDS", address(new CurveAaveDaiInvestableAccountWithRewards()));
    }
    
    function CreateAccount () public {
        account_address = brew_bank.CreateAccount(address(this), "CURVE_AAVE_STABLE_SWAP");
        
        brew_bank.Deposit(20);
        // brew_bank.Withdraw(10);
    }
    
    function CreateAccount1 () public {
        account_address = brew_bank.CreateAccount(address(this), "CURVE_AAVE_STABLE_SWAP_WITH_REWARDS");
        
        // brew_bank.Deposit(20);
        // brew_bank.Withdraw(10);
    }
}

interface AccountFactory {
   function CreateAccount(address account_template_address) external returns (address);
}

interface AccountManager {
   function CreateAccount(address beneficiary_address, uint256 commission_rate_bps, address commission_address, address account_template_address) external returns (address);
    function GetAccount(address beneficiary_address) external returns (address);
}

interface InvestmentManager {
    function AddInvestmentStrategy(string memory strategy_name, address investable_implementation_contract) external;
    function GetInvestmentStrategy(string memory strategy_name) external view returns (address);
}

interface CommissionableAccount {
    function Initialize(uint256 _commission_rate_bps, address _commission_address, address _beneficiary_address) external;
}

interface Investable {
    function Deposit(uint256 amount) external returns (uint256);
    function Withdraw(uint256 amount) external;
    function WithdrawAll() external;
    function WithdrawRewards(address exchange_manager_address) external;
    function WithdrawAllWithRewards(address exchange_manager_address) external;
    function ReinvestRewards(address exchange_manager_address) external;
}

interface StableSwapAave {
    function add_liquidity(uint[3] calldata _amounts,uint _min_mint_amount, bool _use_underlying) external returns (uint256);
    function remove_liquidity_one_coin(uint _token_amount, int128 _i, uint _min_amount, bool _use_underlying) external returns (uint256);
}

interface LiquidityGauge {
    function deposit(uint256 _value, address _addr, bool _claim_rewards) external;
    function withdraw(uint256 _value, bool _claim_rewards) external;
    function claim_rewards() external;
}

interface OneSplitAudit { // interface for 1inch exchange.
    function getExpectedReturn (
        IERC20 fromToken,
        IERC20 toToken,
        uint256 amount,
        uint256 parts,
        uint256 disableFlags
    )
        external
        view
        returns(
            uint256 returnAmount,
            uint256[] memory distribution
        );

    function swap(
        IERC20 fromToken,
        IERC20 toToken,
        uint256 amount,
        uint256 minReturn,
        uint256[] memory distribution,
        uint256 disableFlags
    ) external payable;
}

interface ExchangeManager {
    function exchange(address from_token, address to_token, uint256 amount) external payable returns (uint256);
}

contract BrewBank is Ownable {
    uint256 public commission_rate_bps;
    address public commission_address;
    address public account_manager_address;
    address public investment_manager_address;
    address public exchange_manager_address;
    
    constructor (uint256 _commission_rate_bps, address _commission_address) {
        commission_rate_bps = _commission_rate_bps;
        commission_address = _commission_address;
        
        address account_factory_address = address(new BrewAccountFactory());
        account_manager_address = address(new BrewAccountManager(account_factory_address));
        BrewAccountFactory(account_factory_address).transferOwnership(account_manager_address);
        
        investment_manager_address = address(new BrewInvestmentManager());
        
        exchange_manager_address = address(new Brew1InchExchangeManager());
    }
    
    function CreateAccount(address beneficiary_address, string memory investment_strategy_name) public onlyOwner returns (address) {
        address account_template_address = InvestmentManager(investment_manager_address).GetInvestmentStrategy(investment_strategy_name);
        
        address account_address = AccountManager(account_manager_address).CreateAccount(beneficiary_address, commission_rate_bps, commission_address, account_template_address);
        
        return account_address;
    }
    
    // Methods around operating the account.
    
    function Deposit(uint256 amount) public {
        GetInvestableAccount().Deposit(amount);
    }
    
    function Withdraw(uint256 amount) public {
        GetInvestableAccount().Withdraw(amount);
    }
    
    function WithdrawAll() public {
        GetInvestableAccount().WithdrawAll();
    }
    
    function WithdrawRewards() public {
        GetInvestableAccount().WithdrawRewards(investment_manager_address);
    }
    
    function WithdrawAllWithRewards() public {
        GetInvestableAccount().WithdrawAllWithRewards(investment_manager_address);
    }
    
    function ReinvestRewards() public {
        GetInvestableAccount().ReinvestRewards(investment_manager_address);
    }
    
    function GetInvestableAccount() internal returns (Investable) {
        return Investable(AccountManager(account_manager_address).GetAccount(msg.sender));
    }
    
    // Methods around investment strategies.

    function AddInvestmentStrategy(string memory strategy_name, address investable_implementation_contract) public onlyOwner {
        InvestmentManager(investment_manager_address).AddInvestmentStrategy(strategy_name, investable_implementation_contract);
    }
    
    function GetInvestmentStrategy(string memory strategy_name) public view returns (address) {
        return InvestmentManager(investment_manager_address).GetInvestmentStrategy(strategy_name);
    }
}

contract BrewAccountManager is AccountManager, Ownable {
    address public account_factory_address;
    mapping(address => address) beneficiary_account_address_map;
    
    constructor (address _account_factory_address) {
        account_factory_address = _account_factory_address;
    }
    
    function CreateAccount(address beneficiary_address, uint256 commission_rate_bps, address commission_address, address account_template_address) public onlyOwner returns (address) {
        address account_address = AccountFactory(account_factory_address).CreateAccount(account_template_address);
        
        CommissionableAccount account = CommissionableAccount(account_address);
        account.Initialize(commission_rate_bps, commission_address, address(this));
        
        OwnableUpgradeable(account_address).transferOwnership(owner());
        
        beneficiary_account_address_map[beneficiary_address] = account_address;
        
        return account_address;
    }
    
    function GetAccount(address beneficiary_address) public view returns (address) {
        address account_address = beneficiary_account_address_map[beneficiary_address];
        require(account_address != address(0), "This beneficiary_address does not exist.");
        
        return account_address;
    }
}

contract BrewAccountFactory is AccountFactory, Ownable {
    using Clones for address;
    
    function CreateAccount(address account_template_address) public onlyOwner returns (address) {
        require(account_template_address != address(0), "account_template must be set");
        address account_address = account_template_address.clone();
        
        return account_address; 
    }
}

contract BrewInvestmentManager is InvestmentManager, Ownable {
    mapping(string => address) public investment_strategies;
    
    // New investment strategies can be added at runtime, but older ones can not be edited.
    function AddInvestmentStrategy(string memory strategy_name, address investable_implementation_contract) public onlyOwner {
        require(investment_strategies[strategy_name] == address(0), "This investment strategy name is already added");
        
        investment_strategies[strategy_name] = investable_implementation_contract;
    }
    
    function GetInvestmentStrategy(string memory strategy_name) public view returns (address) {
        address investable_implementation_address = investment_strategies[strategy_name];
        require(investable_implementation_address != address(0), "This investment strategy name does not exist");
        
        return investable_implementation_address;
    }
}

contract BrewCommissionableAccount is Initializable, OwnableUpgradeable, CommissionableAccount {
    uint256 public commission_rate_bps;
    address public commission_address;
    address public beneficiary_address;
    
    function Initialize(uint256 _commission_rate_bps, address _commission_address, address _beneficiary_address) public initializer {
        commission_rate_bps = _commission_rate_bps;
        commission_address = _commission_address;
        beneficiary_address = _beneficiary_address;
        __Ownable_init();
    }
    
    function CalculateCommission(uint256 amount) internal view returns (uint256){
        return (amount * commission_rate_bps)/10000;
    }
}

contract CurveAaveDaiInvestableAccount is Investable, BrewCommissionableAccount {
    address public DAI_ADDRESS = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address public CURVE_AAVE_LP_TOKEN_ADDRESS = 0xE7a24EF0C5e95Ffb0f6684b813A78F2a3AD7D171;
    address public CURVE_AAVE_STABLE_SWAP_SMART_CONTRACT_ADDRESS = 0x445FE580eF8d70FF569aB36e80c647af338db351;
    
    uint256 public principal_amount;
    
    function Deposit(uint256 amount) public onlyOwner virtual returns (uint256) {
        // Transfer the amount from the owner who has already approved this transfer.
        ERC20Utils.ApprovedTransferToSelf(amount, DAI_ADDRESS, beneficiary_address);
        
        return DepositFromSelf(amount);
    }
    
    function DepositFromSelf(uint256 amount) internal returns (uint256) {
        // Approve the allowance of the curve aave smart contract.
        ERC20Utils.Approve(amount, DAI_ADDRESS, CURVE_AAVE_LP_TOKEN_ADDRESS);
        
        uint256 minted_lp_token_amount = StableSwapAave(CURVE_AAVE_STABLE_SWAP_SMART_CONTRACT_ADDRESS).add_liquidity([amount, 0, 0], 0, false);
        
        principal_amount = principal_amount + amount;
        
        return minted_lp_token_amount;
    }
    
    function Withdraw(uint256 lp_token_amount) public onlyOwner virtual {
        require(ERC20Utils.HasBalance(lp_token_amount, CURVE_AAVE_LP_TOKEN_ADDRESS));
        
        uint256 withdrawn_amount = StableSwapAave(CURVE_AAVE_STABLE_SWAP_SMART_CONTRACT_ADDRESS).remove_liquidity_one_coin(lp_token_amount, 0, 0, false);

        // Charge commission only if the withdrawn amount exceeds the principal amount.
        if (withdrawn_amount <= principal_amount) {
            // Reduce the principal amount by the withdran amount.
            principal_amount = principal_amount - withdrawn_amount;
            
            TransferWithoutCommission(withdrawn_amount);
        } else {
            principal_amount = 0;
            
            uint256 excess_amount = withdrawn_amount - principal_amount;
            uint256 commission_amount = CalculateCommission(excess_amount);
                
            TransferWithCommission(withdrawn_amount, commission_amount);
        }
    }
    
    function WithdrawAll() public onlyOwner virtual {
        uint256 total_amount = ERC20Utils.GetBalance(CURVE_AAVE_LP_TOKEN_ADDRESS);
        
        Withdraw(total_amount);
    }
    
    function WithdrawRewards(address exchange_manager_address) public onlyOwner virtual {
        revert("This contract does not support rewards.");
    }
    
    function WithdrawAllWithRewards(address exchange_manager_address) public onlyOwner virtual {
        revert("This contract does not support rewards.");
    }
    
    function ReinvestRewards(address exchange_manager_address) public onlyOwner virtual {
        revert("This contract does not support rewards.");
    }
    
    function TransferWithCommission(uint256 total_amount, uint256 commission_amount) internal {
        ERC20Utils.TransferFromSelf(commission_amount, DAI_ADDRESS, commission_address);
        ERC20Utils.TransferFromSelf(total_amount - commission_amount, DAI_ADDRESS, beneficiary_address);
    }
    
    function TransferWithoutCommission(uint256 total_amount) internal {
        ERC20Utils.TransferFromSelf(total_amount, DAI_ADDRESS, beneficiary_address);
    }
}


contract CurveAaveDaiInvestableAccountWithRewards is CurveAaveDaiInvestableAccount {
    address public LIQUIDITY_GAUGE_CONTRACT_ADDRESS = 0x19793B454D3AfC7b454F206Ffe95aDE26cA6912c;
    address public LIQUIDITY_GAUGE_TOKEN_ADDRESS = 0x19793B454D3AfC7b454F206Ffe95aDE26cA6912c;
    address public WMATIC_TOKEN_ADDRESS = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public CRV_TOKEN_ADDRESS = 0x172370d5Cd63279eFa6d502DAB29171933a610AF;
    
    uint256 public reinvested_amount;
    
    function Deposit(uint256 amount) public override onlyOwner returns (uint256) {
        uint256 minted_lp_token_amount = CurveAaveDaiInvestableAccount.Deposit(amount);
        
        // Approve the allowance of liquidity gauge smart contract.
        ERC20Utils.Approve(amount, CURVE_AAVE_LP_TOKEN_ADDRESS, LIQUIDITY_GAUGE_CONTRACT_ADDRESS);
        
        LiquidityGauge(LIQUIDITY_GAUGE_CONTRACT_ADDRESS).deposit(minted_lp_token_amount, address(this), false);
        
        return minted_lp_token_amount;
    }
    
    function Withdraw(uint256 gauge_token_amount) public override onlyOwner {
        LiquidityGauge(LIQUIDITY_GAUGE_CONTRACT_ADDRESS).withdraw(gauge_token_amount, false);
        
        CurveAaveDaiInvestableAccount.Withdraw(gauge_token_amount);
    }
    
    function WithdrawAll() public override onlyOwner {
        uint256 total_amount = ERC20Utils.GetBalance(LIQUIDITY_GAUGE_TOKEN_ADDRESS);
        Withdraw(total_amount);
    }
    
    function WithdrawRewards(address exchange_manager_address) public onlyOwner override {
        uint256 return_amount = ClaimAndExchangeRewards(exchange_manager_address);
        WithdrawRewardsAfterCommission(return_amount);
    }
    
    function WithdrawAllWithRewards(address exchange_manager_address) public override onlyOwner  {
        WithdrawAll();
        WithdrawRewards(exchange_manager_address);
    }
    
    function ReinvestRewards(address exchange_manager_address) public override {
        uint256 return_amount = ClaimAndExchangeRewards(exchange_manager_address);
        ReinvestRewardsAfterCommission(return_amount);
    }
    
    function ClaimAndExchangeRewards(address exchange_manager_address) internal returns (uint256) {
        LiquidityGauge(LIQUIDITY_GAUGE_CONTRACT_ADDRESS).claim_rewards();
        
        uint256 return_amount = 0;
        return_amount = return_amount + ExchangeRewards(exchange_manager_address, WMATIC_TOKEN_ADDRESS);
        return_amount = return_amount + ExchangeRewards(exchange_manager_address, CRV_TOKEN_ADDRESS);
        
        return return_amount;
    }
    
    function ExchangeRewards(address exchange_manager_address, address reward_token_address) internal returns (uint256){
        ExchangeManager exchange_manager = ExchangeManager(exchange_manager_address);
        
        uint256 balance_amount = ERC20Utils.GetBalance(reward_token_address);
        ERC20Utils.Approve(balance_amount, reward_token_address, exchange_manager_address);
        return exchange_manager.exchange(WMATIC_TOKEN_ADDRESS, DAI_ADDRESS, balance_amount);
    }
    
    function WithdrawRewardsAfterCommission(uint256 return_amount) internal {
        uint256 commission_amount = CalculateCommission(return_amount);
        TransferWithCommission(return_amount, commission_amount);
    }
    
    function ReinvestRewardsAfterCommission(uint256 return_amount) internal {
        uint256 commission_amount = CalculateCommission(return_amount);
        uint256 reinvest_amount = return_amount - commission_amount;
        
        reinvested_amount = reinvested_amount + reinvest_amount;
        
        CurveAaveDaiInvestableAccount.DepositFromSelf(reinvest_amount);
        ERC20Utils.TransferFromSelf(commission_amount, DAI_ADDRESS, commission_address);
    }
    
}

contract Brew1InchExchangeManager is ExchangeManager {
    address ONE_INCH_SMART_CONTRACT_ADDRESS = 0xC586BeF4a0992C495Cf22e1aeEE4E446CECDee0E;
    uint256 PARTS = 10;
    uint256 FLAGS = 0;
    
    function exchange(address from_token, address to_token, uint256 amount) public payable returns (uint256){
        // Transfer the amount from the account which has already approved this transfer.
        ERC20Utils.ApprovedTransferToSelf(amount, DAI_ADDRESS, beneficiary_address);
        
        // Approve the allowance of the one inch smart contract.
        ERC20Utils.Approve(amount, from_token, ONE_INCH_SMART_CONTRACT_ADDRESS);

        (uint256 return_amount, uint256[] memory distribution) = OneSplitAudit(ONE_INCH_SMART_CONTRACT_ADDRESS).getExpectedReturn(IERC20(from_token), IERC20(to_token), amount, PARTS, FLAGS);
        OneSplitAudit(ONE_INCH_SMART_CONTRACT_ADDRESS).swap(IERC20(from_token), IERC20(to_token), amount, return_amount, distribution, FLAGS);
        
        ERC20Utils.TransferFromSelf(return_amount, to_token, msg.sender);
        
        return return_amount;
    }
}

library ERC20Utils {
    function Approve(uint256 amount, address token_address, address spender) internal {
        IERC20(token_address).approve(spender, amount);
    }
    
    function ApprovedTransferToSelf(uint256 amount, address token_address, address sender) internal {
        IERC20(token_address).transferFrom(sender, address(this), amount);
    }
    
    function TransferFromSelf(uint256 amount, address token_address, address recipient) internal {
        IERC20(token_address).transfer(recipient, amount);
    }
    
    function GetBalance(address token_address) internal view returns (uint256) {
        return IERC20(token_address).balanceOf(address(this));
    } 
    
    function HasBalance(uint256 amount, address token_address) internal view returns (bool) {
        return IERC20(token_address).balanceOf(address(this)) >= amount;
    } 
}
