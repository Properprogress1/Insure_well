// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/InsureWell.sol";

contract InsureWellTest is Test {
    InsureWell public insureWell;
    address public owner;
    address public user1;
    address public user2;
    uint256 public constant PREMIUM = 1 ether;
    uint256 public constant DURATION = 2; // 2 years
    uint256 public constant SECONDS_PER_YEAR = 31536000;

    event PolicyCreated(address indexed policyholder, uint256 premium, uint256 duration);
    event ClaimFiled(address indexed policyholder, uint256 amount);
    event RewardClaimed(address indexed policyholder, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event MinContractBalanceUpdated(uint256 newMinBalance);
    event OwnershipTransferInitiated(address indexed currentOwner, address indexed pendingOwner);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Deploy contract
        insureWell = new InsureWell();
        
        // Fund test accounts
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(address(this), 10 ether);
    }

    // Policy Creation Tests
    function testCreatePolicy() public {
        vm.startPrank(user1);
        
        vm.expectEmit(true, true, false, true);
        emit PolicyCreated(user1, PREMIUM, DURATION);
        
        insureWell.createPolicy{value: PREMIUM}(PREMIUM, DURATION);
        
        InsureWell.Policy memory policy = insureWell.getPolicy(user1);
        assertTrue(policy.isActive);
        assertEq(policy.premiumAmount, PREMIUM);
        assertEq(policy.duration, DURATION);
        
        vm.stopPrank();
    }

    function testCreatePolicyInsufficientPremium() public {
        vm.startPrank(user1);
        
        vm.expectRevert("Insufficient premium sent");
        insureWell.createPolicy{value: 0.5 ether}(PREMIUM, DURATION);
        
        vm.stopPrank();
    }

    function testCannotCreateDuplicatePolicy() public {
        vm.startPrank(user1);
        
        insureWell.createPolicy{value: PREMIUM}(PREMIUM, DURATION);
        
        vm.expectRevert();
        insureWell.createPolicy{value: PREMIUM}(PREMIUM, DURATION);
        
        vm.stopPrank();
    }

    function testCannotExceedMaxDuration() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        insureWell.createPolicy{value: PREMIUM}(PREMIUM, 4); // Max duration is 3 years
        
        vm.stopPrank();
    }

    // Reward Tests
    function testClaimReward() public {
        vm.startPrank(user1);
        insureWell.createPolicy{value: PREMIUM}(PREMIUM, DURATION);
        
        // Fast forward 1 year
        skip(SECONDS_PER_YEAR);
        
        uint256 balanceBefore = user1.balance;
        insureWell.claimReward();
        uint256 balanceAfter = user1.balance;
        
        // Expected reward is 4% of premium after 1 year
        uint256 expectedReward = (PREMIUM * 4) / 100;
        assertEq(balanceAfter - balanceBefore, expectedReward);
        
        vm.stopPrank();
    }

    function testClaimRewardMaxYears() public {
        vm.startPrank(user1);
        insureWell.createPolicy{value: PREMIUM}(PREMIUM, DURATION);
        
        // Fast forward 4 years (beyond max years)
        skip(4 * SECONDS_PER_YEAR);
        
        uint256 balanceBefore = user1.balance;
        insureWell.claimReward();
        uint256 balanceAfter = user1.balance;
        
        // Expected reward is 4% * 3 (max years) of premium
        uint256 expectedReward = (PREMIUM * 4 * 3) / 100;
        assertEq(balanceAfter - balanceBefore, expectedReward);
        
        vm.stopPrank();
    }

    function testCannotClaimRewardTooEarly() public {
        vm.startPrank(user1);
        insureWell.createPolicy{value: PREMIUM}(PREMIUM, DURATION);
        
        // Try to claim immediately
        vm.expectRevert();
        insureWell.claimReward();
        
        vm.stopPrank();
    }

    // Contract Management Tests
    function testWithdrawFunds() public {
        // First create a policy to have funds in contract
        vm.prank(user1);
        insureWell.createPolicy{value: PREMIUM}(PREMIUM, DURATION);
        
        uint256 balanceBefore = address(owner).balance;
        insureWell.withdrawFunds(0.5 ether);
        uint256 balanceAfter = address(owner).balance;
        
        assertEq(balanceAfter - balanceBefore, 0.5 ether);
    }

    function testCannotWithdrawBelowMinBalance() public {
        vm.prank(user1);
        insureWell.createPolicy{value: PREMIUM}(PREMIUM, DURATION);
        
        // Try to withdraw more than allowed (keeping min balance)
        vm.expectRevert();
        insureWell.withdrawFunds(2 ether);
    }

    // Ownership Tests
    function testOwnershipTransfer() public {
        address newOwner = makeAddr("newOwner");
        
        // Initiate transfer
        insureWell.initiateOwnershipTransfer(newOwner);
        
        // Claim ownership
        vm.prank(newOwner);
        insureWell.claimOwnership();
        
        assertEq(insureWell.owner(), newOwner);
    }

    function testCannotClaimOwnershipWithoutInitiation() public {
        address unauthorized = makeAddr("unauthorized");
        
        vm.prank(unauthorized);
        vm.expectRevert();
        insureWell.claimOwnership();
    }

    // Policy Status Tests
    function testPolicyActiveStatus() public {
        vm.startPrank(user1);
        insureWell.createPolicy{value: PREMIUM}(PREMIUM, DURATION);
        
        assertTrue(insureWell.isPolicyActive(user1));
        
        // Fast forward beyond policy duration
        skip(3 * SECONDS_PER_YEAR);
        
        // Make a transaction to update the block.timestamp
        vm.prank(user2);
        insureWell.isPolicyActive(user1);
        
        assertFalse(insureWell.isPolicyActive(user1));
        
        vm.stopPrank();
    }

    // Contract Status Tests
    function testContractStatus() public {
        vm.prank(user1);
        insureWell.createPolicy{value: PREMIUM}(PREMIUM, DURATION);
        
        (
            uint256 balance,
            uint256 minimumBalance,
            uint256 totalPremiums,
            uint256 totalClaims,
            uint256 totalRewards,
            bool isPaused
        ) = insureWell.getContractStatus();
        
        assertEq(balance, PREMIUM);
        assertEq(minimumBalance, 1 ether);
        assertEq(totalPremiums, PREMIUM);
        assertEq(totalClaims, 0);
        assertEq(totalRewards, 0);
        assertFalse(isPaused);
    }

    // Pause/Unpause Tests
    function testPauseUnpause() public {
        // Pause contract
        insureWell.pause();
        
        // Try to create policy while paused
        vm.startPrank(user1);
        vm.expectRevert("Pausable: paused");
        insureWell.createPolicy{value: PREMIUM}(PREMIUM, DURATION);
        vm.stopPrank();
        
        // Unpause and verify operations work again
        insureWell.unpause();
        vm.prank(user1);
        insureWell.createPolicy{value: PREMIUM}(PREMIUM, DURATION);
    }

    receive() external payable {}
}