// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
@author Subhajit Das
@title Staking Contract
@dev A contract that allows users to stake tokens, earn rewards, and unstake tokens after a lock-in period.
*/
contract Staking is Ownable {
    uint256 public poolId;
    uint256 public totalStakers;
    uint256 public totalActiveStakers;
    IERC20 public stakingTokenAddress;

    struct Pool {
        uint256 poolDistributionAmount;
        uint256 poolDuration;
        uint256 lockInDuration;
        uint256 totalTokenStaked;
        uint256 totalRewardDistributed;
    }

    struct Stake {
        uint256 stakingAmount;
        uint256 stakedAt;
        uint256 rewardAccumulated;
        uint256 lastClaimedAt;
        bool isActive;
    }
    //poolId -> pool
    mapping(uint256 => Pool) public pools;
    //walletAddress -> poolId -> Stake
    mapping(address => mapping(uint256 => Stake)) public stakes;

    //poolId => address[]
    mapping(uint256 => address[]) public stakers;

    //Errors
    error InvalidZeroAmount();
    error InvalidPoolId();
    error InvalidStaking();
    error PoolTimeOver();

    //modifiers
    modifier validStaking(address _staker, uint256 _poolId) {
        if (_poolId == 0 || _poolId > poolId) revert InvalidStaking();
        if (!stakes[_staker][_poolId].isActive) revert InvalidStaking();
        _;
    }

    //events
    event PoolCreated(
        uint256 poolId,
        uint256 poolDistributionAmount,
        uint256 poolDuration,
        uint256 lockInDuration
    );
    event Staked(address indexed staker, uint256 poolId, uint256 stakingAmount);

    event UnStaked(
        address indexed staker,
        uint256 poolId,
        uint256 unStakingAmount
    );
    event RewardClaimed(
        address indexed staker,
        uint256 poolId,
        uint256 rewardAmount
    );

    /**
     * @dev Initializes the contract with the staking token address.
     * @param _stakingTokenAddress The address of the ERC20 token used for staking.
     */
    constructor(IERC20 _stakingTokenAddress) Ownable(msg.sender) {
        stakingTokenAddress = _stakingTokenAddress;
    }

    /**
     * @dev Creates a new staking pool.
     * @param _poolDistributionAmount The total amount of tokens to be distributed as rewards.
     * @param _poolDuration The duration of the pool in seconds.
     * @param _lockInDuration The lock-in duration in seconds.
     */
    function createPool(
        uint256 _poolDistributionAmount,
        uint256 _poolDuration,
        uint256 _lockInDuration
    ) external {
        if (_poolDistributionAmount == 0) revert InvalidZeroAmount();
        if (_poolDuration == 0) revert InvalidZeroAmount();
        if (_lockInDuration == 0) revert InvalidZeroAmount();

        require(
            stakingTokenAddress.allowance(owner(), address(this)) >=
                _poolDistributionAmount,
            "Token amount is not approved"
        );
        stakingTokenAddress.transferFrom(
            owner(),
            address(this),
            _poolDistributionAmount
        );
        poolId++;
        pools[poolId] = Pool(
            _poolDistributionAmount,
            block.timestamp + _poolDuration,
            _lockInDuration,
            0,
            0
        );
        emit PoolCreated(
            poolId,
            _poolDistributionAmount,
            block.timestamp + _poolDuration,
            _lockInDuration
        );
    }

    /**
     * @dev Allows a user to stake tokens in a pool.
     * @param _stakingAmount The amount of tokens to stake.
     * @param _poolId The ID of the pool to stake in.
     */
    function stake(uint256 _stakingAmount, uint256 _poolId) external {
        if (_stakingAmount == 0) revert InvalidZeroAmount();
        if (_poolId == 0 || _poolId > poolId) revert InvalidPoolId();
        if (pools[poolId].poolDuration < block.timestamp) revert PoolTimeOver();
        require(
            stakingTokenAddress.allowance(_msgSender(), address(this)) >=
                _stakingAmount,
            "Token amount is not approved"
        );
        stakingTokenAddress.transferFrom(
            _msgSender(),
            address(this),
            _stakingAmount
        );

        //if staking already exist add the token amount, else create a new staking
        if (stakes[_msgSender()][_poolId].isActive == true) {
            stakes[_msgSender()][_poolId].stakingAmount += _stakingAmount;
            stakes[_msgSender()][_poolId].stakedAt = block.timestamp;
            stakes[_msgSender()][_poolId].lastClaimedAt = block.timestamp;
        } else {
            //if new user to the platform
            if (stakes[_msgSender()][_poolId].stakedAt == 0) {
                stakers[_poolId].push(_msgSender());
            }
            // add the new staking
            stakes[_msgSender()][_poolId] = Stake(
                _stakingAmount,
                block.timestamp,
                0,
                block.timestamp,
                true
            );
            totalStakers += 1;
            totalActiveStakers += 1;
        }

        pools[poolId].totalTokenStaked += _stakingAmount;
        emit Staked(_msgSender(), _poolId, _stakingAmount);
    }

    /**
     * @dev Allows a user to unstake their tokens after the lock-in period.
     * @param _poolId The ID of the pool to unstake from.
     */
    function unStake(
        uint256 _poolId
    ) external validStaking(_msgSender(), _poolId) {
        Stake storage userStake = stakes[_msgSender()][_poolId];
        Pool storage pool = pools[_poolId];
        require(
            block.timestamp >= userStake.stakedAt + pool.lockInDuration,
            "Lock-in period not over"
        );

        _claim(_msgSender(), _poolId);

        uint256 amountToUnStake = userStake.stakingAmount;
        userStake.stakingAmount = 0;
        userStake.isActive = false;
        pool.totalTokenStaked -= amountToUnStake;
        totalActiveStakers -= 1;
        stakingTokenAddress.transfer(_msgSender(), amountToUnStake);

        emit UnStaked(_msgSender(), _poolId, amountToUnStake);
    }

    /**
     * @dev Allows a user to claim their rewards.
     * @param _poolId The ID of the pool to claim rewards from.
     */
    function claimRewards(
        uint256 _poolId
    ) external validStaking(_msgSender(), _poolId) {
        _claim(_msgSender(), _poolId);
    }

    /**
     * @dev Calculates the reward for a user in a specific pool.
     * @param _staker The address of the staker.
     * @param _poolId The ID of the pool.
     * @return The amount of reward tokens.
     */
    function calculateReward(
        address _staker,
        uint256 _poolId
    ) public view returns (uint256) {
        Pool storage pool = pools[_poolId];
        Stake storage userStake = stakes[_staker][_poolId];

        if (pool.totalTokenStaked == 0) {
            return 0;
        }

        uint256 timeSinceLastClaim = block.timestamp - userStake.lastClaimedAt;
        uint256 daysSinceLastClaim = timeSinceLastClaim / 10 seconds;

        uint256 dailyDistribution = pool.poolDistributionAmount /
            pool.poolDuration;
        uint256 perTokenShare = (dailyDistribution * 1e18) /
            pool.totalTokenStaked;
        uint256 reward = (perTokenShare *
            userStake.stakingAmount *
            daysSinceLastClaim) / 1e18;

        return reward;
    }

    /**
     * @dev Internal function to claim rewards for a staker in a specific pool.
     * @param _staker The address of the staker.
     * @param _poolId The ID of the pool.
     */
    function _claim(address _staker, uint256 _poolId) internal {
        Stake storage userStake = stakes[_staker][_poolId];
        Pool storage pool = pools[_poolId];
        uint256 reward = calculateReward(_staker, _poolId);
        userStake.lastClaimedAt = block.timestamp;
        userStake.rewardAccumulated += reward;
        pool.totalRewardDistributed += reward;
        stakingTokenAddress.transfer(_staker, reward);
        emit RewardClaimed(_staker, _poolId, reward);
    }

    /**
     * @dev Returns the current hourly reward emission for a specific pool.
     * @param _poolId The ID of the pool.
     * @return The amount of tokens distributed per hour.
     */
    function getCurrentHourlyRewardEmission(
        uint256 _poolId
    ) external view returns (uint256) {
        if (_poolId == 0 || _poolId > poolId) revert InvalidPoolId();
        Pool memory pool = pools[_poolId];
        uint256 dailyDistribution = pool.poolDistributionAmount /
            pool.poolDuration;
        return dailyDistribution / 24;
    }

    /**
     * @dev Returns the total pool amount left for distribution.
     * @param _poolId The ID of the pool.
     * @return The amount of tokens left for distribution.
     */
    function getTotalPoolAmountLeft(
        uint256 _poolId
    ) external view returns (uint256) {
        if (_poolId == 0 || _poolId > poolId) revert InvalidPoolId();
        Pool memory pool = pools[_poolId];
        return pool.poolDistributionAmount - pool.totalRewardDistributed;
    }

    /**
     * @dev Returns the total tokens staked in a specific pool.
     * @param _poolId The ID of the pool.
     * @return The total amount of tokens staked.
     */
    function getTokenStakedInPool(
        uint256 _poolId
    ) external view returns (uint256) {
        return pools[_poolId].totalTokenStaked;
    }

    /**
     * @dev Returns the list of stakers in a specific pool.
     * @param _poolId The ID of the pool.
     * @param _isActive If true, returns only active stakers. If false, returns all stakers.
     * @return An array of staker addresses.
     */
    function getAllStakersList(
        uint256 _poolId,
        bool _isActive
    ) external view returns (address[] memory) {
        if (_poolId == 0 || _poolId > poolId) revert InvalidPoolId();

        if (_isActive) {
            uint256 count = 0;

            for (uint256 i = 0; i < stakers[_poolId].length; i++) {
                if (stakes[stakers[_poolId][i]][_poolId].isActive) {
                    count++;
                }
            }

            address[] memory allStakers = new address[](count);
            uint256 idx = 0;

            for (uint256 i = 0; i < stakers[_poolId].length; i++) {
                if (stakes[stakers[_poolId][i]][_poolId].isActive) {
                    allStakers[idx] = stakers[_poolId][i];
                    idx++;
                }
            }

            return allStakers;
        } else {
            return stakers[_poolId];
        }
    }
}
