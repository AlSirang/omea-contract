// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

error ContractIsPaused();
error Deposit404();
error DepositIsLocked();
error LowContractBalance();
error OwnerError();
error ZeroAddress();
error ZeroDeposit();

contract OMEA is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint24 public constant WITHDRAW_PERIOD = 30 days; // 30 days
    uint24 private constant REWARD_PERIOD = 1 hours;
    // REFERRER REWARDS
    uint16 private constant REFERRER_REWARD_1 = 800; // 800 : 8 %. 10000 : 100 %
    uint16 private constant REFERRER_REWARD_2 = 900; // 900 : 9 %. 10000 : 100 %
    uint16 private constant REFERRER_REWARD_3 = 1000; // 1000 : 10 %. 10000 : 100 %
    // HPR (Hourly Percentage Rate)
    uint16 private constant HPR_5 = 15; // 350 : 3.50 %. 10000 : 100 %
    uint16 private constant HPR_4 = 12; // 300 : 3.00 %. 10000 : 100 %
    uint16 private constant HPR_3 = 10; // 250 : 2.50 %. 10000 : 100 %
    uint16 private constant HPR_2 = 8; // 200 : 2.00 %. 10000 : 100 %
    uint16 private constant HPR_1 = 7; // 6 : 0.06 %. 10000 : 100 %
    // FEEs
    uint8 public constant DEV_FEE = 200; // 200 : 2 %. 10000 : 100 %
    uint8 public constant MARKETING_FEE = 200; // 200 : 2 %. 10000 : 100 %
    uint8 public constant PRINCIPAL_FEE = 100; // 100 : 1%. 10000 : 100 %

    address public immutable i_BUSD_CONTRACT;

    address private devWallet;
    address private marketingWallet;

    uint256 private _totalValueLocked;
    uint256 private _totalInvestors;
    uint256 private _totalRewardsDistributed;

    bool private _isLaunched;

    mapping(address => Deposit[]) private _depositsHistory;
    mapping(address => Investor) public investors;
    mapping(address => bool) private _isActiveInvestor;
    mapping(address => Bonus[]) private _bonusHistory;

    /*************************************************/
    /******************** STRUCTS ********************/
    /*************************************************/

    struct Bonus {
        uint256 amount;
        uint256 createdDate;
    }
    struct Deposit {
        uint256 index; // deposit index
        address depositor; // address of wallet
        uint256 amount; // amount deposited
        uint256 lockPeriod;
        bool status; // if deposit amount is withdraw => false
    }

    struct Investor {
        address account; // wallet address of investor
        address referrer; // wallet referrer of investor
        uint256 totalInvested; // sum of all deposits
        uint256 lastCalculatedBlock; // timestamp for last time when rewards were updated
        uint256 claimableAmount; // pending rewards to be claimed
        uint256 claimedAmount; // claimed amount
        uint256 referAmount; // amount generated from referrals
        uint256 referrals; // number of referrals
        uint256 bonus; // amount of bonuses
    }

    /*************************************************/
    /******************** EVENTS ********************/
    /*************************************************/

    event Deposited(address indexed investor, uint256 amount);

    /*************************************************/
    /******************* FUNCTIONS *******************/
    /*************************************************/

    function deposit(uint256 _amount, address _referrer) external {
        if (!_isLaunched) revert ContractIsPaused();
        if (_amount < 1) revert ZeroDeposit();

        IERC20(i_BUSD_CONTRACT).safeTransferFrom(
            _msgSender(),
            address(this),
            _amount
        );

        // DevFee
        uint256 _developerFee = (_amount * DEV_FEE) / 10000;
        IERC20(i_BUSD_CONTRACT).safeTransfer(devWallet, _developerFee);

        // Marketing Fee
        uint256 _marketingFee = (_amount * MARKETING_FEE) / 10000;
        IERC20(i_BUSD_CONTRACT).safeTransfer(marketingWallet, _marketingFee);

        uint256 _depositAmount = _amount - (_developerFee + _marketingFee);
        uint256 deposits = _depositsHistory[_msgSender()].length;

        Deposit memory _deposit = Deposit({
            index: deposits,
            depositor: _msgSender(),
            amount: _depositAmount,
            lockPeriod: block.timestamp + WITHDRAW_PERIOD,
            status: true
        });
        _depositsHistory[_msgSender()].push(_deposit);

        if (_referrer == _msgSender()) _referrer = address(0);
        bool isActiveInvestor_ = _isActiveInvestor[_msgSender()];

        if (!isActiveInvestor_) {
            investors[_msgSender()] = Investor({
                account: _msgSender(),
                lastCalculatedBlock: block.timestamp,
                referrer: _referrer,
                totalInvested: _depositAmount,
                claimableAmount: 0,
                claimedAmount: 0,
                referAmount: 0,
                referrals: 0,
                bonus: 0
            });

            _totalInvestors += 1;
            _isActiveInvestor[_msgSender()] = true;
        } else {
            Investor memory investor_ = investors[_msgSender()];

            uint256 _totalInvested = investor_.totalInvested + _depositAmount;
            investor_ = _updateInvestorRewards(investor_);
            investor_.totalInvested = _totalInvested;
            investors[_msgSender()] = investor_;
        }

        Investor memory _investor = investors[_msgSender()];
        if (_investor.referrer == address(0x0) && _referrer != address(0x0)) {
            _investor.referrer = _referrer;

            Investor memory referrer_ = investors[_referrer];
            uint256 _totalReferrals = referrer_.referrals + 1;

            referrer_.referrals = _totalReferrals;

            uint256 _referrerAmount = _calculateReferralRewards(
                _amount,
                _totalReferrals
            );
            referrer_.referAmount += _referrerAmount;

            IERC20(i_BUSD_CONTRACT).safeTransfer(_referrer, _referrerAmount);
        }

        _totalValueLocked += _amount;

        emit Deposited(_msgSender(), _amount);
    }

    /**
     * @dev calculates claimable rewards and send to  _msgSender()
     */
    function claimAllReward() external nonReentrant {
        if (_depositsHistory[_msgSender()].length == 0) revert Deposit404();

        Investor memory investor_ = investors[_msgSender()];

        investor_ = _updateInvestorRewards(investor_);

        uint256 allClaimables = investor_.claimableAmount;

        uint256 sendBalance = allClaimables;
        if (getBalance() < allClaimables) {
            sendBalance = getBalance();
        }
        investor_.claimableAmount = allClaimables - sendBalance;
        investor_.claimedAmount = sendBalance;

        investors[_msgSender()] = investor_;

        IERC20(i_BUSD_CONTRACT).safeTransfer(_msgSender(), sendBalance);

        _totalRewardsDistributed += sendBalance;
    }

    /**
     * @dev calculates claimable rewards and send capital invested
     */
    function withdrawCapital(uint256 _depositIndex) external nonReentrant {
        uint256 _totalDeposits = _depositsHistory[_msgSender()].length - 1;

        if (_totalDeposits < _depositIndex) revert Deposit404();

        Deposit memory _deposit = _depositsHistory[_msgSender()][_depositIndex];

        if (!_deposit.status) revert Deposit404();
        if (_deposit.lockPeriod > block.timestamp) revert DepositIsLocked();
        if (_deposit.depositor != _msgSender()) revert OwnerError();

        Investor memory investor_ = investors[_msgSender()];

        investor_ = _updateInvestorRewards(investor_);

        uint256 depositCapital = _deposit.amount;

        if (depositCapital > getBalance()) revert LowContractBalance();

        investor_.totalInvested -= depositCapital;

        _totalValueLocked -= depositCapital;

        //  if withdraws all amount remove bonuses
        if (investor_.totalInvested == 0) {
            delete _bonusHistory[_msgSender()];
            investor_.bonus = 0;
        }

        investors[_msgSender()] = investor_;
        _deposit.status = false;
        _depositsHistory[_msgSender()][_depositIndex] = _deposit;

        uint256 _principalFee = (depositCapital * PRINCIPAL_FEE) / 10000;
        depositCapital -= _principalFee;

        // transfer capital to the user
        IERC20(i_BUSD_CONTRACT).safeTransfer(_msgSender(), depositCapital);
    }

    /*************************************************/
    /*************** PRIVATE FUNCTIONS ***************/
    /*************************************************/
    /**
     * @dev  checks if address is contract.
     */
    function isContract(address _addr) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    /**
     * @dev  calculates and udpate claimables for _investor.
     */
    function _updateInvestorRewards(Investor memory investor_)
        private
        view
        returns (Investor memory)
    {
        (
            uint256 claimables,
            uint256 lastCalculatedBlock
        ) = _calculateClaimableAmount(investor_);

        investor_.claimableAmount += claimables;
        investor_.lastCalculatedBlock = lastCalculatedBlock;

        return investor_;
    }

    /**
     * @dev  calculates claimable amount for _investor.
     */
    function _calculateClaimableAmount(Investor memory _investor)
        private
        view
        returns (uint256 claimables, uint256 lastCalculatedBlock)
    {
        uint256 hoursInSec = block.timestamp - _investor.lastCalculatedBlock;
        uint256 _totalLocked = _investor.totalInvested + _investor.bonus;

        uint256 tokensPerHour = (_totalLocked * getHPR(_totalLocked)) / 10000;
        uint256 hoursSinceLastCheck = hoursInSec / REWARD_PERIOD;

        claimables = (tokensPerHour * hoursSinceLastCheck);
        lastCalculatedBlock = block.timestamp;
    }

    /**
     * @dev  calculate referral rewards for given _deposit and number of _referrals count
     */
    function _calculateReferralRewards(uint256 _deposit, uint256 _referrals)
        private
        pure
        returns (uint256)
    {
        return (_deposit * getReferralBPs(_referrals)) / 10000;
    }

    /*************************************************/
    /**************** ADMIN FUNCTIONS ****************/
    /*************************************************/

    function addBonus(address _account, uint256 _amount) external onlyOwner {
        require(_isActiveInvestor[_account], "No investor 404");

        Investor memory _investor = investors[_account];

        uint256 _totalBonus = _investor.bonus + _amount;
        require(_totalBonus < 1000 ether, "Bonus limit reached");

        _investor = _updateInvestorRewards(_investor);
        _investor.bonus = _totalBonus;

        Bonus memory bonus = Bonus({
            amount: _amount,
            createdDate: block.timestamp
        });

        _bonusHistory[_account].push(bonus);
        investors[_account] = _investor;
    }

    function launchContract() external onlyOwner {
        _isLaunched = true;
    }

    /**
     * @dev updates dev wallet address
     */
    function resetDevWallet(address _devWallet) external onlyOwner {
        if (_devWallet == address(0x0)) revert ZeroAddress();
        devWallet = _devWallet;
    }

    /**
     * @dev updates marketing wallet address
     */
    function resetMarketingWallet(address _marketingWallet) external onlyOwner {
        if (_marketingWallet == address(0x0)) revert ZeroAddress();
        marketingWallet = _marketingWallet;
    }

    /*************************************************/
    /**************** VIEW FUNCTIONS ****************/
    /************************************************/

    function getInvestmentInfo()
        external
        view
        returns (
            uint256 totalInvestors,
            uint256 totalValueLocked,
            uint256 totalRewardsDistributed
        )
    {
        totalInvestors = _totalInvestors;
        totalValueLocked = _totalValueLocked;
        totalRewardsDistributed = _totalRewardsDistributed;
    }

    /**
     * @dev returns BUSD balance of contract.
     */
    function getBalance() public view returns (uint256) {
        return IERC20(i_BUSD_CONTRACT).balanceOf(address(this));
    }

    /**
     * @dev returns amount of pending rewards for _account
     */
    function getClaimableAmount(address _account)
        public
        view
        returns (uint256)
    {
        Investor memory _investor = investors[_account];
        (uint256 claimables, ) = _calculateClaimableAmount(_investor);
        return (claimables + _investor.claimableAmount);
    }

    /**
     * @dev returns percentage (in bps) for number of referrals
     */
    function getReferralBPs(uint256 _referrals) public pure returns (uint16) {
        if (_referrals == 0) return 0;
        if (_referrals <= 10) return REFERRER_REWARD_1;
        if (_referrals <= 30) return REFERRER_REWARD_2;
        return REFERRER_REWARD_3;
    }

    /**
     * @dev returns Hourly Percentage Rate (in bps) for _investment. _investment should be in wei
     */
    function getHPR(uint256 _investment) public pure returns (uint16) {
        if (_investment < 1) return 0;
        if (_investment < 101 ether) return HPR_1;
        if (_investment < 501 ether) return HPR_2;
        if (_investment < 1001 ether) return HPR_3;
        if (_investment < 5001 ether) return HPR_4;
        return HPR_5;
    }

    /**
     * @dev returns all deposits of _account
     */
    function depositsOf(address _account)
        external
        view
        returns (Deposit[] memory)
    {
        return _depositsHistory[_account];
    }

    /**
     * @dev returns all bonuses of _account
     */
    function bonusOf(address _account) external view returns (Bonus[] memory) {
        return _bonusHistory[_account];
    }

    /**
     * @dev returns status of contract i.e open for depoists
     */
    function isLaunched() external view returns (bool) {
        return _isLaunched;
    }

    /*************************************************/
    /****************** CONSTRUCTOR ******************/
    /*************************************************/
    constructor(
        address _devWallet,
        address _marketingWallet,
        address _busdContract
    ) {
        if (
            !isContract(_busdContract) ||
            _devWallet == address(0x0) ||
            _marketingWallet == address(0x0)
        ) revert ZeroAddress();

        devWallet = _devWallet;
        marketingWallet = _marketingWallet;
        i_BUSD_CONTRACT = _busdContract;
    }
}
