// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/InvestmentPlatform.sol";
import "../src/ERC20Token.sol";
import "forge-std/Vm.sol";


contract InvestmentPlatformTest is Test {
    InvestmentPlatform private platform;
    ERC20Token private token;
        address public admin;
    address private user1;
    address private user2;
    address private user3;
    address private user4;
    address private user5;
    

    function setUp() public {
        vm.startPrank(address(0x6));
        token = new ERC20Token(10000000000000000000000000001000000000000000000000000000); // Deploy your ERC20 token contract

      //  token.mint(address(0x1), initialBalance);
        platform = new InvestmentPlatform(address(token)); // Deploy the contract
        vm.stopPrank();
        user1 = address(0x01);
        user2 = address(0x02);
        user3 = address(0x03);
        user4 = address(0x04);
        user5 = address(0x05);
    }

    function testStakeTokens() public {
        uint256 initialBalance = 1000 ether; // Initial balance of the user
        uint256 stakeAmount = 500 ether; // Amount to stake

        vm.startPrank(address(0x6));
        token.transfer(user1, 1000 ether);
        // vm.stopPrank();
        // vm.startPrank(address(0x1));

      //  token.mint(address(0x1), initialBalance);
        // Ensure that the user has enough tokens to stake
        assert(token.balanceOf(address(0x1)) > stakeAmount); // "Insufficient balance for staking"
                // Mint tokens for the user
        // Approve the platform contract to spend user's tokens
        token.approve(address(platform), stakeAmount);

        // Stake tokens on the platform
        try platform.stakeTokens(stakeAmount, address(0)) {
            (uint256 stakedAmountresp, uint256 stakingEndTime, uint256 startDate, uint256 totalWithdrawn, uint256 lastClaimTime) = platform.userStaking(address(this), 0);

            // Check the user's staked balance
            assertEq(stakedAmountresp, stakeAmount, "Incorrect staked amount");

            // Check the user's total invested amount
            assertEq(platform.totalInvestedAmount(address(this)), stakeAmount, "Incorrect total invested amount");

            // Check the user's staking end time
            assertEq(stakingEndTime, block.timestamp + platform.STAKING_DURATION(), "Incorrect staking end time");
        } catch Error(string memory) {
            //Assert.fail("StakeTokens transaction reverted unexpectedly");
        }
        vm.stopPrank();

    }

    function testUserInvitation() public {
        // Deploy a new ERC20 token contract
        ERC20Token token = new ERC20Token(1000000000000000000000000000);
        
        // Deploy the InvestmentPlatform contract with the ERC20 token address
        InvestmentPlatform platform = new InvestmentPlatform(address(token));

        // User A
        address userA = address(0x1);
        uint256 stakeAmount = 100 ether; // Amount to stake
        address userB = address(0x2); // User B's address
        uint256 referralReward = 5 ether; // Direct sponsor income for user A
        
        // Mint tokens for user A
        token.mint(userA, 1000 ether);
        assertEq(token.balanceOf(userA), 1000 ether, "User A balance should be 1000 ether");
        
        // Mint tokens for user B
        token.mint(userB, 1000 ether);
        assertEq(token.balanceOf(userB), 1000 ether, "User B balance should be 1000 ether");

        // Start the prank from user B's address
        vm.startPrank(address(userB));

        // User B purchases a plan with User A as referrer
        token.approve(address(platform), stakeAmount);
        platform.stakeTokens(stakeAmount, userA);
        
        // End the prank
        vm.stopPrank();
        
        // Check user A's rewards after User B's purchase
        assertEq(platform.totalReferralRewards(userA), referralReward, "Incorrect referral rewards for User A");
    }


      function testCheckInvestorRank() public {
        // Assuming 'token' is an instance of the ERC20 token contract
        uint256 amount = 100000000000000000000000000000000000000; // Example: 1e38 tokens

        vm.startPrank(address(0x06));

        // Approve tokens for the InvestmentPlatform contract
        token.approve(address(platform), amount);

        token.transfer(user1, 1000 ether);

        token.transfer(user2, 2000 ether);
        token.transfer(user3, 3000 ether);
        token.transfer(user4, 4000 ether);
        token.transfer(user5, 5000 ether);
        
        console2.log("a1");

        vm.stopPrank();
        console2.log("a2");

        console2.log("a2");
        vm.startPrank(address(0x01));
        token.approve(address(platform), 100 ether);

        platform.stakeTokens(100 ether, address(0x06));
        vm.stopPrank();

        vm.startPrank(address(0x02));
        token.approve(address(platform), 200 ether);
        platform.stakeTokens(200 ether, address(0x06));
        vm.stopPrank();

        // platform.stakeTokens(300000000000000000000, address(0x06));
        // platform.stakeTokens(400000000000000000000, address(0x06));
        console2.log("a2");

        vm.startPrank(address(0x06));

        platform.addToWhitelist(user1);
        platform.addToWhitelist(user2);
        platform.addToWhitelist(user3);
        platform.addToWhitelist(user4);
        platform.addToWhitelist(user5);
        vm.stopPrank();

        platform.setDirectAndIndirectUsers(user1, admin);
        platform.setDirectAndIndirectUsers(user2, user1);
        platform.setDirectAndIndirectUsers(user3, user1);
        platform.setDirectAndIndirectUsers(user4, user2);
        platform.setDirectAndIndirectUsers(user5, user2);

        assert(platform.getUserRank(user1) == InvestmentPlatform.Rank.Investor);
        assert(platform.getUserRank(user2) == InvestmentPlatform.Rank.Investor);

    }

// Steps: 
// Deposit 0x01 100 Tokens
// Stake Tokens(0x01)
// Call the rewards after 1 mins
// (Stake End Duration ( 1 min) )

    function testWithdrawal() public {
        vm.startPrank(address(0x6));
        token.transfer(address(0x05), 100 ether);

        platform.addToWhitelist(address(0x05));


        platform.addToWhitelist(user1);
        platform.addToWhitelist(user2);
        platform.addToWhitelist(user3);
        platform.addToWhitelist(user4);
        platform.addToWhitelist(user5);
        vm.stopPrank();

        vm.startPrank(address(0x05));

        // Approve tokens for the InvestmentPlatform contract
        token.approve(address(platform), 100 ether); // Approve 100 ether tokens for InvestmentPlatform contract

        // Make a deposit to have rewards available for withdrawal
        //platform.stakeTokens{value: 10 ether}(10 ether, address(0));
        platform.stakeTokens(100 ether, platform.admin());

        uint256 amount = 100000000000000000000000000000000000000; // Example: 1e38 tokens

        vm.startPrank(address(0x06));

        // Approve tokens for the InvestmentPlatform contract
        token.approve(address(platform), amount);

        token.transfer(user1, 1000 ether);

        token.transfer(user2, 2000 ether);
        token.transfer(user3, 3000 ether);
        token.transfer(user4, 4000 ether);
        token.transfer(user5, 5000 ether);
        

        vm.stopPrank();

        vm.startPrank(address(0x02));
        token.approve(address(platform), 100 ether);

        platform.stakeTokens(100 ether, address(0x06));
        vm.stopPrank();

        vm.startPrank(address(0x03));
        token.approve(address(platform), 200 ether);
        platform.stakeTokens(200 ether, address(0x02));
        vm.stopPrank();
        // Claim rewards to have some rewards available
        //platform.claimRewards();

        // Get the initial contract balance
        uint initialContractBalance = address(platform).balance;

        vm.startPrank(address(0x02));
          //  vm.roll(block.timestamp + 5);
          // 1 
        vm.warp(16);

        console2.log(platform.checkRewards(address(0x02)));
        vm.warp(32);
        console2.log(platform.checkRewards(address(0x02)));

        vm.warp(55);
        console2.log(platform.checkRewards(address(0x02)));

        platform.claimRewards();

        // Get the initial user rewards balance
       // uint initialUserRewardsBalance = platform.totalRewardsReceived(address(this));


        // Withdraw 1 ether
        uint withdrawalAmount = 1 ether;
       // platform.withdraw(withdrawalAmount);
        vm.stopPrank();

        // Check the contract balance after withdrawal
     //   assertEq(address(platform).balance, initialContractBalance - withdrawalAmount, "Contract balance should decrease by withdrawal amount");

        // Check the user rewards balance after withdrawal
      //  assertEq(platform.totalRewardsReceived(address(this)), initialUserRewardsBalance - withdrawalAmount, "User rewards balance should decrease by withdrawal amount");
    }

    // Steps: 
    // Deposit 0x01 100 Tokens
    // Stake Tokens(0x01, admin)
    // Call the rewards after 1 mins
    // (Stake End Duration ( 1 min) )
    function testDemo() public {

        vm.startPrank(address(0x6));
        token.transfer(address(0x02), 100 ether);
        platform.addToWhitelist(address(0x02));
        vm.stopPrank();
        vm.startPrank(address(0x02));
        token.approve(address(platform), 100 ether);

        platform.stakeTokens(100 ether, platform.admin());
        vm.stopPrank();
        console2.log(platform.checkRewards(address(0x02)));
        
        vm.warp(55);
        console2.log(platform.checkRewards(address(0x02)));
    }
}
