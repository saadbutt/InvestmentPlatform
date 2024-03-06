// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract InvestmentPlatform is ReentrancyGuard {
    address public admin;
    ERC20 public token;

    uint256 public constant MAX_REFERRAL_LIMIT = 3;
    uint256 public constant MIN_STAKING_AMOUNT = 100 ether;
    uint256 public multiplier = 10**18;

    uint256 public constant STAKING_DURATION = 60 minutes; //60 minutes; :todo need to change

    uint256 public constant MAX_WITHDRAWAL_MULTIPLIER = 3;
    uint256 public constant REWARD_PERCENTAGE_PER_SECOND = 5e15; // 0.5% in 18 decimals
    uint256 public constant WITHDRAWAL_FEE_PERCENTAGE = 10; // 10% withdrawal fee
    uint256 public constant DIRECT_SPONSOR_INCOME_PERCENTAGE = 5;

    uint256 public constant WEEKLY_SALARY_PERIOD = 1 weeks; // Weekly salary distribution period
    mapping(uint256 => address[]) public levelUsersArray;
    uint256 public lastWeeklyRewardsDistribution;

    enum Rank {
        Investor,
        Silver,
        Gold,
        Diamond,
        BlueDiamond,
        Platinum,
        Ambassador,
        AmbassadorPlus,
        GlobalAmbassador
    }
    
    struct UserStaking {
        uint256 stakedAmount;
        uint256 stakingEndTime;
        uint256 startDate;
        uint256 totalWithdrawn;
        uint256 lastClaimTime;
    }

    struct Rewards {
        uint256 totalRewards;
        uint256 dailyRewards;
        uint256 lastClaimTime;
    }

    struct User_children {
        address[] child;
    }

    mapping(address => UserStaking[]) public userStaking;
    mapping(address => uint) public totalInvestedAmount;
    mapping(address => Rewards) public userRewards;
    mapping(address => Rewards) public userReferralRewards;
    mapping(address => address) public parent;
    mapping(address => User_children) private referrerToDirectChildren;
    mapping(address => User_children) private referrerToIndirectChildren;
    mapping(uint => mapping(address => address[])) public levelUsers;
    mapping(uint => mapping(address => uint)) public levelCountUsers;
    mapping(address => uint256) public maxTierReferralCounts;
    mapping(address => uint256) public rewardAmount;
    mapping(address => bool) public userValidation;
    mapping(address => bool) public blacklist;
    mapping(address => bool) public whitelist;

    // Mapping to track last salary distribution time for each user
    mapping(address => uint256) public lastSalaryDistributionTime;

    event SalaryIncomeClaimed(address indexed user, uint256 amount);
    event TokensStaked(address indexed user, uint256 amount, uint256 endTime);
    event RewardsClaimed(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount, uint256 fees);
    // Define event to indicate rank achieved and rewards start time
    event RankAchieved(address indexed user, Rank rank, uint256 rewardsAmount, uint256 rewardsStartTime);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }

    modifier notBlacklisted(address _user) {
        require(!blacklist[_user], "User is blacklisted");
        _;
    }

    modifier whitelisted(address _user) {
        require(whitelist[_user], "User is not whitelisted");
        _;
    }

    constructor(address _tokenAddress) {
        token = ERC20(_tokenAddress);
        admin = msg.sender;
    }

  function stakeTokens(uint256 tokenAmount, address referrer) public nonReentrant notBlacklisted(msg.sender) {
    require(tokenAmount >= MIN_STAKING_AMOUNT, "Amount needs to be at least 100");
    require(msg.sender != admin, "Admin cannot stake");

    if (parent[msg.sender] == address(0)) {
        parent[msg.sender] = referrer;

        setDirectAndIndirectUsers(msg.sender, referrer);
        setLevelUsers(msg.sender, referrer);
    } else {

        require(referrer == parent[msg.sender], "Referrer must be the same");
    }

    uint256 stakingEndTime = block.timestamp + STAKING_DURATION;
    uint256 startDate = block.timestamp;

    UserStaking memory newStake = UserStaking({
        stakedAmount: tokenAmount,
        stakingEndTime: stakingEndTime,
        startDate: startDate,
        totalWithdrawn: 0,
        lastClaimTime: block.timestamp
    });

    userStaking[msg.sender].push(newStake);

    totalInvestedAmount[msg.sender] += tokenAmount;

    // Update referral rewards for the referrer
    updateReferralRewards(msg.sender, tokenAmount);

    // Check if user achieves a new rank upon deposit
    Rank currentRank = getUserRank(msg.sender);
    if (currentRank != Rank.Investor) { // Only proceed if the user achieves a rank higher than Investor
        uint256 rewardsAmount = getWeeklySalary(currentRank);
        uint256 rewardsStartTime = block.timestamp + 1 days; // Start rewards from the next day

        // Emit an event to indicate that the user achieved a new rank and rewards will start from a certain date
        emit RankAchieved(msg.sender, currentRank, rewardsAmount, rewardsStartTime);
    }

    distributeWeeklyRewards();

    token.transferFrom(msg.sender, address(this), tokenAmount);

    emit TokensStaked(msg.sender, tokenAmount, stakingEndTime);
}

function distributeWeeklyRewards() internal {
    if(block.timestamp >= lastWeeklyRewardsDistribution + WEEKLY_SALARY_PERIOD) {
        return;
    }
    
    // Update the last weekly rewards distribution time
    lastWeeklyRewardsDistribution = block.timestamp;

    // Iterate over each level to distribute rewards
    for (uint i = 1; i <= 15; i++) {
        address[] memory users = levelUsersArray[i];
        for (uint j = 0; j < users.length; j++) {
            address user = users[j];
            if (userValidation[user]) { // Check if the user is valid
                uint256 rewardsAmount = calculateWeeklyReward(user); // Calculate the weekly reward
                if (rewardsAmount > 0) {
                    // Transfer the rewards to the user
                    token.transfer(user, rewardsAmount);
                    emit SalaryIncomeClaimed(user, rewardsAmount);
                }
            }
        }
    }
}

function calculateWeeklyReward(address user) internal returns (uint256) {
    uint256 rewardsAmount = 0;
    Rank currentRank = getUserRank(user);
    if (currentRank == Rank.Gold) {
        rewardsAmount = 100 * multiplier;
    } else if (currentRank == Rank.Diamond) {
        rewardsAmount = 200 * multiplier;
    } else if (currentRank == Rank.BlueDiamond) {
        rewardsAmount = 500 * multiplier;
    } else if (currentRank == Rank.Platinum) {
        rewardsAmount = 1000 * multiplier;
    } else if (currentRank == Rank.Ambassador) {
        rewardsAmount = 2000 * multiplier;
    } else if (currentRank == Rank.AmbassadorPlus) {
        rewardsAmount = 4000 * multiplier;
    } else if (currentRank == Rank.GlobalAmbassador) {
        rewardsAmount = 8000 * multiplier;
    }
    return rewardsAmount;
}

// Define function to get weekly salary based on rank
function getWeeklySalary(Rank rank) internal pure returns (uint256) {
    if (rank == Rank.Gold) {
        return 100 * 1 ether; // $100 in wei
    } else if (rank == Rank.Diamond) {
        return 200 * 1 ether; // $200 in wei
    } else if (rank == Rank.BlueDiamond) {
        return 500 * 1 ether; // $500 in wei
    } else if (rank == Rank.Platinum) {
        return 1000 * 1 ether; // $1000 in wei
    } else if (rank == Rank.Ambassador) {
        return 2000 * 1 ether; // $2000 in wei
    } else if (rank == Rank.AmbassadorPlus) {
        return 4000 * 1 ether; // $4000 in wei
    } else if (rank == Rank.GlobalAmbassador) {
        return 8000 * 1 ether; // $8000 in wei
    } else {
        return 0; // No salary for lower ranks
    }
}

function updateReferralRewards(address user, uint256 stakedAmount) internal {
    address referrer = parent[user];
    if (referrer != address(0)) {
        uint256 referralReward = (stakedAmount * DIRECT_SPONSOR_INCOME_PERCENTAGE) / 100;
        userReferralRewards[referrer].totalRewards += referralReward;
    }
}

function claimRewards() public nonReentrant notBlacklisted(msg.sender) whitelisted(msg.sender) {
    updateRewards(msg.sender);
    updateReferralRewardsOnClaim(msg.sender); // Update referral rewards

    Rewards storage rewards = userRewards[msg.sender];
    uint256 claimableRewards = rewards.totalRewards;
    
    require(claimableRewards > 0, "No rewards to claim");

    rewards.totalRewards = 0;
    rewards.lastClaimTime = block.timestamp;

    token.transfer(msg.sender, claimableRewards);

    emit RewardsClaimed(msg.sender, claimableRewards);
}

function updateReferralRewardsOnClaim(address user) internal {

    address referrer = parent[user];
    if (referrer != address(0)) {
        uint256 referralReward = userReferralRewards[referrer].totalRewards;

        if (referralReward > 0) {
            userReferralRewards[referrer].totalRewards = 0;
          //  token.transfer(referrer, referralReward);
            userRewards[user].totalRewards += referralReward;

        }
    }
}

    function updateRewards(address user) internal {
        UserStaking[] storage stakes = userStaking[user];
        Rewards storage rewards = userRewards[user];

        for (uint256 i = 0; i < stakes.length; i++) {
            if (block.timestamp > stakes[i].stakingEndTime) {
                uint256 stakingDuration = stakes[i].stakingEndTime - stakes[i].startDate;
                uint256 secondsSinceLastClaim = block.timestamp - stakes[i].lastClaimTime;

                // Calculate rewards per second and update total and daily rewards
                uint256 rewardPerSecond = (stakes[i].stakedAmount * REWARD_PERCENTAGE_PER_SECOND) / 1e18;
                uint256 totalReward = rewardPerSecond * secondsSinceLastClaim;

                // Ensure total rewards excluding rank rewards do not exceed 3x
                if (totalReward > 3 * stakes[i].stakedAmount) {
                    totalReward = (3 * stakes[i].stakedAmount);
                }

                rewards.totalRewards += totalReward;
                rewards.dailyRewards += totalReward;

                stakes[i].lastClaimTime = block.timestamp; // Update last claim time
                stakes[i].stakingEndTime = block.timestamp; // Reset staking end time to the current time
            }
        }
    }

    function checkRewards(address user) public view returns (uint256) {
    UserStaking[] storage stakes = userStaking[user];
    uint256 totalRewards = 0;

    for (uint256 i = 0; i < stakes.length; i++) {
        uint256 stakingDuration = stakes[i].stakingEndTime - stakes[i].startDate;
        uint256 secondsSinceLastClaim = block.timestamp - stakes[i].lastClaimTime;

        // Calculate rewards per second
        uint256 rewardPerSecond = (stakes[i].stakedAmount * REWARD_PERCENTAGE_PER_SECOND) / 1e18;

        // Calculate total rewards since last claim
        uint256 rewardsSinceLastClaim = rewardPerSecond * secondsSinceLastClaim;
        // Ensure total rewards excluding rank rewards do not exceed 3x
        if (rewardsSinceLastClaim > 3 * stakes[i].stakedAmount) {
            rewardsSinceLastClaim = (3 * stakes[i].stakedAmount);
        }

        // Add rewards since last claim to total rewards
        totalRewards += rewardsSinceLastClaim;
    }

    return totalRewards;
}



    function withdraw(uint256 amountInEther) public nonReentrant notBlacklisted(msg.sender) whitelisted(msg.sender) {
        require(amountInEther > 0, "Withdrawal amount must be greater than 0");
            // Convert ether amount to wei
        uint256 amountInWei = amountInEther * 1 ether;
        emit Withdrawal(msg.sender,userRewards[msg.sender].totalRewards,userRewards[msg.sender].totalRewards);
        require(amountInWei <= userRewards[msg.sender].totalRewards, "Insufficient rewards");

        uint256 withdrawalFees = (amountInWei * WITHDRAWAL_FEE_PERCENTAGE) / 100;
        uint256 withdrawableAmount = amountInWei - withdrawalFees;

        require(withdrawableAmount <= userRewards[msg.sender].totalRewards, "Insufficient rewards after fees");
        require(withdrawableAmount <= (totalInvestedAmount[msg.sender] * MAX_WITHDRAWAL_MULTIPLIER), "Exceeds withdrawal limit");

        userRewards[msg.sender].totalRewards -= amountInWei;

        uint256 totalAmount = amountInWei + withdrawalFees;
        require(token.balanceOf(address(this)) >= totalAmount, "Insufficient contract balance");

        token.transfer(msg.sender, withdrawableAmount);
        token.transfer(admin, withdrawalFees);

        emit Withdrawal(msg.sender, amountInWei, withdrawalFees);
    }

    function calculateRewards(address user, uint256 index) internal view returns (uint256) {
        UserStaking storage staking = userStaking[user][index];
        uint256 totalRewards = userRewards[user].totalRewards;

        if (block.timestamp > staking.stakingEndTime) {
            uint256 stakingDuration = staking.stakingEndTime - staking.startDate;
            uint256 reward = (staking.stakedAmount * REWARD_PERCENTAGE_PER_SECOND * stakingDuration) / 1e18;
            totalRewards += reward;
        }

        return totalRewards;
    }

    function totalReferralRewards(address user) public view returns (uint256) {
        return userReferralRewards[user].totalRewards;
    }

function setDirectAndIndirectUsers(address _user, address _referrer) public {
    // Add the user as a direct child of the referrer
    referrerToDirectChildren[_referrer].child.push(_user);    
    setIndirectUsersRecursive(_user, _referrer);
    updateLevelIncome(_user);
}

function setLevelUsers(address _user, address _referrer) internal {
    address currentReferrer = _referrer;
    for (uint i = 1; i <= 15; i++) {
        if (!isUserInArray(_user, levelUsers[i][currentReferrer])) {
            levelUsers[i][currentReferrer].push(_user);
            levelCountUsers[i][currentReferrer]++;
            levelUsersArray[i].push(_user); // Add user to the array at level i
        }

        if (currentReferrer == admin) {
            break;
        } else {
            currentReferrer = parent[currentReferrer];
        }
    }
}

// Function to check if a user is already in the array
function isUserInArray(address _user, address[] memory _array) internal pure returns (bool) {
    for (uint256 i = 0; i < _array.length; i++) {
        if (_array[i] == _user) {
            return true;
        }
    }
    return false;
}

function updateLevelIncome(address user) internal {
    address currentReferrer = parent[user];
    uint256 stakedAmount = 0; // Initialize stakedAmount to zero

    // Check if user has any staking history
    if (userStaking[user].length > 0) {
        stakedAmount = userStaking[user][userStaking[user].length - 1].stakedAmount; // Use last staking amount
    } else {
        // Handle the case where the user has no staking history
        // You can choose to revert, emit an event, or take any other appropriate action
        //revert("User has no staking history");
        return;
    }

    uint256 levelIncome;
    for (uint i = 1; i <= 15; i++) {
        if (currentReferrer == address(0)) {
            break;
        }
        if (levelCountUsers[i][currentReferrer] >= i) {
            if (i == 1) {
                levelIncome = (stakedAmount * 50) / 100; // 50% for 1st level
            } else if (i >= 2 && i <= 3) {
                levelIncome = (stakedAmount * 10) / 100; // 10% for 2nd and 3rd level
            } else if (i >= 4 && i <= 6) {
                levelIncome = (stakedAmount * 5) / 100; // 5% for 4th to 6th level
            } else if (i >= 7 && i <= 8) {
                levelIncome = (stakedAmount * 1) / 100; // 1% for 7th and 8th level
            } else {
                levelIncome = (stakedAmount * 1) / 100; // 1% for 9th to 15th level
            }
            // ASk: Distribute level income on staking
            userRewards[currentReferrer].totalRewards += levelIncome; 
        }
        currentReferrer = parent[currentReferrer];
    }
}


    function setIndirectUsersRecursive(address _user, address _referrer) internal {
        address presentReferrer = parent[_referrer];

        // Ensure that we have a valid referrer and avoid infinite loop
        while (presentReferrer != address(0) && presentReferrer != admin) {
            // Add the user as an indirect child of the current referrer
            referrerToIndirectChildren[presentReferrer].child.push(_user);
            
            // Move to the next level up in the referral hierarchy
            presentReferrer = parent[presentReferrer];
        }
    }


    function showAllDirectChild(address user) external view returns (address[] memory) {
        address[] memory children = referrerToDirectChildren[user].child;

        return children;
    }

    function showAllInDirectChild(address user) external view returns (address[] memory) {
        address[] memory children = referrerToIndirectChildren[user].child;

        return children;
    }

    function totalRewardsReceived(address userAddress) public view returns (uint256) {
        require(userAddress != address(0), "Invalid address");

        uint256 totalRewards = userReferralRewards[userAddress].totalRewards + userRewards[userAddress].totalRewards;

        return totalRewards;
    }

    function transferOwnership(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Invalid new admin address");
        admin = newAdmin;
    }

    function addToBlacklist(address user) public onlyAdmin {
        blacklist[user] = true;
    }

    function removeFromBlacklist(address user) public onlyAdmin {
        blacklist[user] = false;
    }

    function addToWhitelist(address user) public onlyAdmin {
        whitelist[user] = true;
    }

    function removeFromWhitelist(address user) public onlyAdmin {
        whitelist[user] = false;
    }

    function getTotalRewardsPerSecond(address user) public view returns (uint256) {
        uint256 totalRewards = userRewards[user].totalRewards;

        UserStaking[] storage stakes = userStaking[user];
        for (uint256 i = 0; i < stakes.length; i++) {
            if (block.timestamp > stakes[i].stakingEndTime) {
                uint256 stakingDuration = stakes[i].stakingEndTime - stakes[i].startDate;
                uint256 secondsSinceLastClaim = stakes[i].lastClaimTime;// block.timestamp - stakes[i].lastClaimTime;

                // Calculate rewards per second and update total rewards
                uint256 rewardPerSecond = (stakes[i].stakedAmount * REWARD_PERCENTAGE_PER_SECOND) / 1e18;
                uint256 totalReward = rewardPerSecond * secondsSinceLastClaim;

                totalRewards += totalReward;
            }
        }

        return totalRewards;
    }

    function getUserRank(address user) public view returns (Rank) {
    uint256 directReferrals = referrerToDirectChildren[user].child.length;

    uint256 directTeamBusiness = 0;
    uint256 totalTeamBusiness = 0;
    address[] memory directChildren = referrerToDirectChildren[user].child;

    // Calculate direct team business
    for (uint256 i = 0; i < directChildren.length; i++) {
        address child = directChildren[i];
        directTeamBusiness += totalInvestedAmount[child];
    }

    // Calculate total team business (including indirect referrals)
    totalTeamBusiness = calculateTotalTeamBusiness(user);

    if (checkGlobalAmbassadorRank(user)) {
        return Rank.GlobalAmbassador;
    }

    if (checkAmbassadorPlusRank(user)) {
        return Rank.AmbassadorPlus;
    }

    if (checkAmbassadorRank(user)) {
        return Rank.Ambassador;
    }

    if (checkPlatinumRank(user)) {
        return Rank.Platinum;
    }

    if (checkBlueDiamondRank(user)) {
        return Rank.BlueDiamond;
    }

    if (checkDiamondRank(user)) {
        return Rank.Diamond;
    }

    if (directReferrals >= 8 && directTeamBusiness >= 5000 ether && totalTeamBusiness >= 30000 ether) {
        return Rank.Gold;
    }

    if (directReferrals >= 6 && directTeamBusiness >= 3000 ether && totalTeamBusiness >= 20000 ether) {
        return Rank.Silver;
    }

    if (directReferrals >= 3 && directTeamBusiness >= 1000 ether && totalTeamBusiness >= 10000 ether) {
        return Rank.Investor;
    }
}

    function calculateTotalTeamBusiness(address user) internal view returns (uint256) {
        uint256 totalTeamBusiness = 0;
        address[] memory indirectChildren = referrerToIndirectChildren[user].child;

        // Calculate total team business (including indirect referrals)
        for (uint256 i = 0; i < indirectChildren.length; i++) {
            address child = indirectChildren[i];
            totalTeamBusiness += totalInvestedAmount[child];
        }

        return totalTeamBusiness;
    }

    function checkDiamondRank(address user) internal view returns (bool) {
        // Check if the user has 3 Gold ranks in separate legs
        uint256 goldRanksCount = 0;
        address[] memory directChildren = referrerToDirectChildren[user].child;

        for (uint256 i = 0; i < directChildren.length; i++) {
            address child = directChildren[i];
            if (getUserRank(child) == Rank.Gold) {
                goldRanksCount++;
                if (goldRanksCount >= 3) {
                    return true;
                }
            }
        }

        return false;
    }

    function checkBlueDiamondRank(address user) internal view returns (bool) {
        // Check if the user has 3 Diamond ranks in separate legs
        uint256 diamondRanksCount = 0;
        address[] memory directChildren = referrerToDirectChildren[user].child;

        for (uint256 i = 0; i < directChildren.length; i++) {
            address child = directChildren[i];
            if (getUserRank(child) == Rank.Diamond) {
                diamondRanksCount++;
                if (diamondRanksCount >= 3) {
                    return true;
                }
            }
        }

        return false;
    }

    function checkPlatinumRank(address user) internal view returns (bool) {
        // Check if the user has 3 Blue Diamond ranks in separate legs
        uint256 blueDiamondRanksCount = 0;
        address[] memory directChildren = referrerToDirectChildren[user].child;

        for (uint256 i = 0; i < directChildren.length; i++) {
            address child = directChildren[i];
            if (getUserRank(child) == Rank.BlueDiamond) {
                blueDiamondRanksCount++;
                if (blueDiamondRanksCount >= 3) {
                    return true;
                }
            }
        }

        return false;
    }

    function checkAmbassadorRank(address user) internal view returns (bool) {
        // Check if the user has 3 Platinum ranks in separate legs
        uint256 platinumRanksCount = 0;
        address[] memory directChildren = referrerToDirectChildren[user].child;

        for (uint256 i = 0; i < directChildren.length; i++) {
            address child = directChildren[i];
            if (getUserRank(child) == Rank.Platinum) {
                platinumRanksCount++;
                if (platinumRanksCount >= 3) {
                    return true;
                }
            }
        }

        return false;
    }

    function checkAmbassadorPlusRank(address user) internal view returns (bool) {
        // Check if the user has 3 Ambassador ranks in separate legs
        uint256 ambassadorRanksCount = 0;
        address[] memory directChildren = referrerToDirectChildren[user].child;

        for (uint256 i = 0; i < directChildren.length; i++) {
            address child = directChildren[i];
            if (getUserRank(child) == Rank.Ambassador) {
                ambassadorRanksCount++;
                if (ambassadorRanksCount >= 3) {
                    return true;
                }
            }
        }

        return false;
    }

    function checkGlobalAmbassadorRank(address user) internal view returns (bool) {
        // Check if the user has 3 Ambassador Plus ranks in separate legs
        uint256 ambassadorPlusRanksCount = 0;
        address[] memory directChildren = referrerToDirectChildren[user].child;

        for (uint256 i = 0; i < directChildren.length; i++) {
            address child = directChildren[i];
            if (getUserRank(child) == Rank.AmbassadorPlus) {
                ambassadorPlusRanksCount++;
                if (ambassadorPlusRanksCount >= 3) {
                    return true;
                }
            }
        }

        return false;
    }

}
