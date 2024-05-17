// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
contract Staking is Ownable {
    uint public poolId;
    uint public totalStakers;
    uint public totalActiveStakers;
    IERC20 public stakingTokenAddress;

    struct Pool {
        uint256 poolDistributionAmount;
        uint256 poolDuration;
        uint256 lockInDuration;
        uint256 totalTokenStaked;
    }

    struct Stake {
        uint256 stakeAmount;
        uint256 stateAt;
        bool isActive;
    }
    //poolId -> pool
    mapping(uint => Pool) public pools;
    //walletAddress -> poolId -> Stake
    mapping(address => mapping(uint => Stake)) public stakes;

    //Errors
    error InvalidZeroAmount();
    error InvalidPoolId();

    //events
    event PoolCreated(
        uint poolId,
        uint poolDistributionAmount,
        uint poolDuration,
        uint lockInDuration
    );

    constructor(IERC20 _stakingTokenAddress) Ownable(msg.sender) {
        stakingTokenAddress = _stakingTokenAddress;
    }

    function createPool(
        uint _poolDistributionAmount,
        uint _poolDuration,
        uint _lockInDuration
    ) external onlyOwner {
        if (_poolDistributionAmount == 0) revert InvalidZeroAmount();
        if (_poolDuration == 0) revert InvalidZeroAmount();
        if (_lockInDuration == 0) revert InvalidZeroAmount();

        require(
            stakingTokenAddress.allowance(owner(), address(this)) ==
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
            _poolDuration,
            _lockInDuration,
            0
        );
        emit PoolCreated(
            poolId,
            _poolDistributionAmount,
            _poolDuration,
            _lockInDuration
        );
    }

    function stake(uint _stakingAmount, uint _poolId) external {
        if (_stakingAmount == 0) revert InvalidZeroAmount();
        if (_poolId == 0 || _poolId > poolId) revert InvalidPoolId();
        require(
            stakingTokenAddress.allowance(_msgSender(), address(this)) ==
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
            stakes[_msgSender()][_poolId].stateAt = block.timestamp;
        } else {
            stakes[_msgSender()][_poolId] = Stake(
                _stakingAmount,
                block.timestamp,
                true
            );
            totalStakers += 1;
            totalActiveStakers += 1;
        }
        pools[poolId].totalTokenStaked += _stakingAmount;
    }

    function unStake(uint _poolId) external {
        if (_poolId == 0 || _poolId > poolId) revert InvalidPoolId();
    }
}
