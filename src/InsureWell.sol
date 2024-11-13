// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract InsureWell is ReentrancyGuard, Pausable {
    using Address for address payable;

    struct Policy {
        uint256 premiumAmount;
        uint256 startTime;
        uint256 duration;
        bool hasClaim;
        bool isActive;
        uint256 lastRewardClaim;
        uint256 totalRewardsClaimed;
    }

    address public owner;
    address public pendingOwner;
    uint256 private constant SECONDS_PER_YEAR = 31536000;
    uint256 private constant REWARD_PERCENTAGE = 4;
    uint256 private constant MAX_YEARS = 3;
    uint256 private constant MIN_PREMIUM = 0.1 ether;
    uint256 public totalPremiumsCollected;
    uint256 public totalClaimsPaid;
    uint256 public totalRewardsPaid;
    uint256 public minContractBalance;

    mapping(address => Policy) public policies;
    mapping(address => uint256) public pendingRewards;

    // Events
    event PolicyCreated(address indexed policyholder, uint256 premium, uint256 duration);
    event ClaimFiled(address indexed policyholder, uint256 amount);
    event RewardClaimed(address indexed policyholder, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event MinContractBalanceUpdated(uint256 newMinBalance);
    event OwnershipTransferInitiated(address indexed currentOwner, address indexed pendingOwner);

    // Errors
    error InsufficientPremium(uint256 sent, uint256 required);
    error InvalidDuration(uint256 duration);
    error PolicyAlreadyExists();
    error PolicyNotFound();
    error ClaimAlreadyFiled();
    error ExcessiveClaimAmount(uint256 requested, uint256 maximum);
    error PolicyNotMatured();
    error InsufficientContractBalance();
    error BelowMinimumBalance();
    error UnauthorizedOwnershipClaim();
    error InvalidAddress();

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyPolicyHolder() {
        if (!_isPolicyHolder(msg.sender)) revert PolicyNotFound();
        _;
    }

    constructor() {
        owner = msg.sender;
        minContractBalance = 1 ether;
    }

    // Ownership Transfer Functions
    function initiateOwnershipTransfer(address newOwner) external onlyOwner {
        if (newOwner == address(0) || newOwner == owner) revert InvalidAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferInitiated(owner, newOwner);
    }

    function claimOwnership() external {
        if (msg.sender != pendingOwner) revert UnauthorizedOwnershipClaim();
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    /// @notice Sets a new minimum balance required for the contract to maintain after withdrawals
    /// @param newMinBalance New minimum balance required
    function setMinContractBalance(uint256 newMinBalance) external onlyOwner {
        minContractBalance = newMinBalance;
        emit MinContractBalanceUpdated(newMinBalance);
    }

    /// @notice Allows the owner to withdraw funds while ensuring a minimum contract balance
    /// @param amount The amount to withdraw
    function withdrawFunds(uint256 amount) external onlyOwner nonReentrant whenNotPaused {
        unchecked {
            if (address(this).balance - amount < minContractBalance) revert BelowMinimumBalance();
        }
        payable(owner).sendValue(amount);
    }

    // Policy Management Functions
    /// @notice Allows a user to create a new policy with a specified premium and duration
    function createPolicy(uint256 premium, uint256 duration) external payable whenNotPaused nonReentrant {
        require(msg.value >= premium, "Insufficient premium sent");
        if (policies[msg.sender].isActive) revert PolicyAlreadyExists();
        if (duration > MAX_YEARS) revert InvalidDuration(duration);

        policies[msg.sender] = Policy({
            premiumAmount: premium,
            startTime: block.timestamp,
            duration: duration,
            hasClaim: false,
            isActive: true,
            lastRewardClaim: block.timestamp,
            totalRewardsClaimed: 0
        });
        totalPremiumsCollected += premium;

        emit PolicyCreated(msg.sender, premium, duration);
    }

    /// @notice Allows policyholders to claim rewards if eligible
    function claimReward() external onlyPolicyHolder nonReentrant whenNotPaused {
        Policy storage policy = policies[msg.sender];
        if (policy.hasClaim) revert ClaimAlreadyFiled();

        uint256 rewardAmount = _calculateReward(policy);
        if (rewardAmount == 0) revert PolicyNotMatured();

        policy.lastRewardClaim = block.timestamp;
        policy.totalRewardsClaimed += rewardAmount;
        totalRewardsPaid += rewardAmount;

        finalizePolicy(policy);

        (bool sent, ) = payable(msg.sender).call{value: rewardAmount}("");
        require(sent, "Failed to send reward");

        emit RewardClaimed(msg.sender, rewardAmount);
    }

    /// @notice Gets the maximum amount the policyholder can claim
    /// @param policyholder The address of the policyholder
    /// @return The maximum claim amount
    function getMaxClaimAmount(address policyholder) external view returns (uint256) {
        Policy storage policy = policies[policyholder];
        return (!policy.isActive || policy.hasClaim) ? 0 : policy.premiumAmount;
    }

    /// @notice Gets the available reward for the policyholder
    /// @param policyholder The address of the policyholder
    /// @return The available reward amount
    function getAvailableReward(address policyholder) external view returns (uint256) {
        Policy storage policy = policies[policyholder];
        return (!policy.isActive || policy.hasClaim) ? 0 : _calculateReward(policy);
    }

    /// @notice Checks if the policy is still active
    /// @param policyholder The address of the policyholder
    function isPolicyActive(address policyholder) public view returns (bool) {
        return _isPolicyHolder(policyholder);
    }

    // Internal Functions for Reward Calculation and Policy Management
    /// @dev Calculates the reward amount based on the time elapsed
    function _calculateReward(Policy storage policy) internal view returns (uint256) {
        uint256 yearsElapsed = (block.timestamp - policy.lastRewardClaim) / SECONDS_PER_YEAR;
        if (yearsElapsed > MAX_YEARS) {
            return (policy.premiumAmount * REWARD_PERCENTAGE * MAX_YEARS) / 100;
        }
        return (policy.premiumAmount * REWARD_PERCENTAGE * yearsElapsed) / 100;
    }

    /// @dev Finalizes the policy if the duration has ended
    function finalizePolicy(Policy storage policy) internal {
        uint256 endTime = policy.startTime + (policy.duration * SECONDS_PER_YEAR);
        if (block.timestamp >= endTime) {
            policy.isActive = false;
        }
    }


    function getPolicy(address _policyHolder) public view returns (Policy memory) {
    return policies[_policyHolder];
}


    /// @dev Internal function to check if the address is a valid policyholder
    function _isPolicyHolder(address policyholder) internal view returns (bool) {
        Policy storage policy = policies[policyholder];
        return policy.isActive && (block.timestamp < policy.startTime + (policy.duration * SECONDS_PER_YEAR));
    }


    function pause() external onlyOwner {
    _pause();
}

function unpause() external onlyOwner {
    _unpause();
}

    // Contract Status Functions
    /// @notice Returns the contract's status and important metrics
    function getContractStatus() external view returns (
        uint256 balance,
        uint256 minimumBalance,
        uint256 totalPremiums,
        uint256 totalClaims,
        uint256 totalRewards,
        bool isPaused
    ) {
        return (
            address(this).balance,
            minContractBalance,
            totalPremiumsCollected,
            totalClaimsPaid,
            totalRewardsPaid,
            paused()
        );
    }
}
