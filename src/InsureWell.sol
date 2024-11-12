// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract InsureWell is ReentrancyGuard {
    struct Policy {
        uint256 premiumAmount;
        uint256 startTime;
        uint256 duration;
        bool hasClaim;
        bool isActive;
    }
    
    address public owner;
    uint256 private constant SECONDS_PER_YEAR = 31536000;
    uint256 private constant REWARD_PERCENTAGE = 4;
    uint256 private constant MAX_YEARS = 3;
    uint256 private constant MIN_PREMIUM = 0.1 ether;
    
    mapping(address => Policy) public policies;
    
    event PolicyCreated(address indexed policyholder, uint256 premium, uint256 duration);
    event ClaimFiled(address indexed policyholder, uint256 amount);
    event RewardClaimed(address indexed policyholder, uint256 amount);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyPolicyHolder() {
        require(policies[msg.sender].isActive && isPolicyActive(msg.sender), "No active policy found or policy expired");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    function createPolicy(uint256 _durationInYears) external payable {
        require(msg.value >= MIN_PREMIUM, "Premium must be at least the minimum premium amount");
        require(_durationInYears > 0 && _durationInYears <= MAX_YEARS, "Duration must be between 1 and 3 years");
        require(!policies[msg.sender].isActive, "Policy already exists");
        
        policies[msg.sender] = Policy({
            premiumAmount: msg.value,
            startTime: block.timestamp,
            duration: _durationInYears,
            hasClaim: false,
            isActive: true
        });
        
        emit PolicyCreated(msg.sender, msg.value, _durationInYears);
    }
    
    function fileClaim(uint256 _claimAmount) external onlyPolicyHolder nonReentrant {
        Policy storage policy = policies[msg.sender];
        require(!policy.hasClaim, "Claim already filed");
        require(_claimAmount <= policy.premiumAmount, "Claim amount exceeds premium");
        
        policy.hasClaim = true;
        payable(msg.sender).transfer(_claimAmount);
        
        emit ClaimFiled(msg.sender, _claimAmount);
    }
    
    function claimReward() external onlyPolicyHolder nonReentrant {
        Policy storage policy = policies[msg.sender];
        require(!policy.hasClaim, "Cannot claim reward after filing a claim");
        require(block.timestamp >= policy.startTime + (policy.duration * SECONDS_PER_YEAR), "Policy not matured yet");
        
        uint256 rewardAmount = (policy.premiumAmount * REWARD_PERCENTAGE * policy.duration) / 100;
        policy.isActive = false;
        
        payable(msg.sender).transfer(rewardAmount);
        
        emit RewardClaimed(msg.sender, rewardAmount);
    }
    
    function getPolicyDetails() external view returns (
        uint256 premium,
        uint256 startTime,
        uint256 duration,
        bool hasClaim,
        bool isActive
    ) {
        Policy storage policy = policies[msg.sender];
        return (
            policy.premiumAmount,
            policy.startTime,
            policy.duration,
            policy.hasClaim,
            isPolicyActive(msg.sender)
        );
    }
    
    function withdrawFunds(uint256 amount) external onlyOwner nonReentrant {
        require(amount <= address(this).balance, "Insufficient funds");
        payable(owner).transfer(amount);
    }
    
    function isPolicyActive(address policyholder) public view returns (bool) {
        Policy storage policy = policies[policyholder];
        return policy.isActive && (block.timestamp < policy.startTime + (policy.duration * SECONDS_PER_YEAR));
    }
    
    receive() external payable {}
}
