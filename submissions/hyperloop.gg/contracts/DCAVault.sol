// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./HypurrAutoLoopVault.sol";

/**
 * @title DCAVault
 * @notice Extension of HypurrAutoLoopVault with Dollar-Cost Averaging functionality
 * @dev Allows users to deposit stables and incrementally loop into HYPE over time
 * 
 * Key Features:
 * - DCA from stables (USDXL) into leveraged HYPE positions
 * - Configurable DCA schedules (amount, frequency, duration)
 * - Keeper-triggered execution with LTV/HF safety checks
 * - Automatic position building over time to reduce timing risk
 */
contract DCAVault is HypurrAutoLoopVault {
    
    // ============ Structs ============

    struct DCAConfig {
        uint256 totalAmount;        // Total USDXL to DCA
        uint256 amountPerExecution; // USDXL amount per DCA execution
        uint256 frequency;          // Seconds between executions
        uint256 maxLTV;             // Maximum LTV to respect (in basis points)
        uint256 minHF;              // Minimum HF to maintain (in 18 decimals)
        uint256 lastExecutionTime;  // Timestamp of last execution
        uint256 executedAmount;     // Total amount executed so far
        bool active;                // Whether DCA is active
    }

    // ============ State Variables ============

    /// @notice DCA configurations per user
    mapping(address => DCAConfig) public dcaConfigs;

    /// @notice USDXL deposits pending DCA execution
    mapping(address => uint256) public pendingDCADeposits;

    /// @notice Keeper addresses authorized to execute DCA
    mapping(address => bool) public keepers;

    // ============ Events ============

    event DCAConfigured(
        address indexed user,
        uint256 totalAmount,
        uint256 amountPerExecution,
        uint256 frequency,
        uint256 maxLTV,
        uint256 minHF
    );
    event DCAExecuted(
        address indexed user,
        uint256 usdxlAmount,
        uint256 assetAmount,
        uint256 newCollateral,
        uint256 newDebt
    );
    event DCACancelled(address indexed user, uint256 refundedAmount);
    event KeeperAdded(address indexed keeper);
    event KeeperRemoved(address indexed keeper);

    // ============ Errors ============

    error DCANotActive();
    error DCANotReady();
    error InsufficientDCABalance();
    error UnauthorizedKeeper();
    error DCAAlreadyActive();
    error InvalidDCAConfig();

    // ============ Constructor ============

    constructor(
        address _asset,
        address _hypurrPool,
        address _usdxl,
        address _swapRouter,
        address _treasury,
        string memory _name,
        string memory _symbol
    ) HypurrAutoLoopVault(
        _asset,
        _hypurrPool,
        _usdxl,
        _swapRouter,
        _treasury,
        _name,
        _symbol
    ) {}

    // ============ Modifiers ============

    modifier onlyKeeper() {
        if (!keepers[msg.sender] && msg.sender != owner()) {
            revert UnauthorizedKeeper();
        }
        _;
    }

    // ============ DCA Configuration Functions ============

    /**
     * @notice Configure DCA strategy for caller
     * @param totalAmount Total USDXL to DCA over time
     * @param amountPerExecution USDXL amount per execution
     * @param frequency Seconds between executions
     * @param maxLTV Maximum LTV in basis points (e.g., 7000 = 70%)
     * @param minHF Minimum health factor to maintain (18 decimals)
     */
    function configureDCA(
        uint256 totalAmount,
        uint256 amountPerExecution,
        uint256 frequency,
        uint256 maxLTV,
        uint256 minHF
    ) external nonReentrant {
        if (dcaConfigs[msg.sender].active) revert DCAAlreadyActive();
        if (totalAmount == 0 || amountPerExecution == 0 || frequency == 0) {
            revert InvalidDCAConfig();
        }
        if (amountPerExecution > totalAmount) revert InvalidDCAConfig();
        if (maxLTV > 9000 || maxLTV < 5000) revert InvalidDCAConfig(); // 50-90%
        if (minHF < 1e18) revert InvalidDCAConfig();

        // Transfer USDXL from user
        usdxl.safeTransferFrom(msg.sender, address(this), totalAmount);
        pendingDCADeposits[msg.sender] += totalAmount;

        // Configure DCA
        dcaConfigs[msg.sender] = DCAConfig({
            totalAmount: totalAmount,
            amountPerExecution: amountPerExecution,
            frequency: frequency,
            maxLTV: maxLTV,
            minHF: minHF,
            lastExecutionTime: block.timestamp,
            executedAmount: 0,
            active: true
        });

        emit DCAConfigured(
            msg.sender,
            totalAmount,
            amountPerExecution,
            frequency,
            maxLTV,
            minHF
        );
    }

    /**
     * @notice Execute DCA for a user (called by keeper)
     * @param user Address of user to execute DCA for
     */
    function executeDCA(address user) external onlyKeeper nonReentrant {
        DCAConfig storage config = dcaConfigs[user];
        
        if (!config.active) revert DCANotActive();
        if (block.timestamp < config.lastExecutionTime + config.frequency) {
            revert DCANotReady();
        }
        if (pendingDCADeposits[user] < config.amountPerExecution) {
            revert InsufficientDCABalance();
        }

        // Calculate amount to execute (min of amountPerExecution and remaining)
        uint256 remainingAmount = config.totalAmount - config.executedAmount;
        uint256 executeAmount = config.amountPerExecution > remainingAmount 
            ? remainingAmount 
            : config.amountPerExecution;

        // Check current LTV and HF before execution
        (
            uint256 totalCollateral,
            uint256 totalDebt,
            ,
            uint256 currentLTV,
            ,
            uint256 healthFactor
        ) = hypurrPool.getUserAccountData(address(this));

        // Only execute if within safety parameters
        if (currentLTV > config.maxLTV * 1e2) { // Convert basis points to HypurrFi format
            revert DCANotReady(); // Wait for better conditions
        }
        if (healthFactor < config.minHF) {
            revert HealthFactorTooLow();
        }

        // Swap USDXL to asset
        uint256 assetAmount = _swapUSDXLToAsset(executeAmount);

        // Supply as collateral
        hypurrPool.supply(address(asset), assetAmount, address(this), 0);

        // Optionally borrow more USDXL and loop (mini-loop)
        uint256 borrowAmount = _calculateSafeBorrowAmount(
            totalCollateral + assetAmount,
            totalDebt,
            config.maxLTV,
            config.minHF
        );

        if (borrowAmount > 0) {
            // Borrow USDXL
            hypurrPool.borrow(address(usdxl), borrowAmount, 2, 0, address(this));
            
            // Swap and re-supply
            uint256 additionalAsset = _swapUSDXLToAsset(borrowAmount);
            hypurrPool.supply(address(asset), additionalAsset, address(this), 0);
        }

        // Update state
        config.lastExecutionTime = block.timestamp;
        config.executedAmount += executeAmount;
        pendingDCADeposits[user] -= executeAmount;

        // Check if DCA is complete
        if (config.executedAmount >= config.totalAmount) {
            config.active = false;
        }

        // Get new position
        (uint256 newCollateral, uint256 newDebt, , , , ) = hypurrPool.getUserAccountData(address(this));

        emit DCAExecuted(user, executeAmount, assetAmount, newCollateral, newDebt);
    }

    /**
     * @notice Calculate safe borrow amount respecting LTV and HF limits
     * @param collateral Current collateral value
     * @param debt Current debt value
     * @param maxLTV Maximum LTV in basis points
     * @param minHF Minimum health factor
     * @return borrowAmount Safe amount to borrow
     */
    function _calculateSafeBorrowAmount(
        uint256 collateral,
        uint256 debt,
        uint256 maxLTV,
        uint256 minHF
    ) internal pure returns (uint256 borrowAmount) {
        // Calculate max debt based on LTV
        uint256 maxDebtFromLTV = (collateral * maxLTV) / 10000;
        
        // Calculate max debt based on HF
        // HF = collateral / debt, so debt = collateral / HF
        uint256 maxDebtFromHF = (collateral * 1e18) / minHF;

        // Take the more conservative limit
        uint256 maxDebt = maxDebtFromLTV < maxDebtFromHF ? maxDebtFromLTV : maxDebtFromHF;

        // Calculate additional borrowing capacity
        if (maxDebt > debt) {
            borrowAmount = maxDebt - debt;
            // Apply 90% safety margin
            borrowAmount = (borrowAmount * 9000) / 10000;
        } else {
            borrowAmount = 0;
        }
    }

    /**
     * @notice Cancel DCA and refund remaining USDXL
     */
    function cancelDCA() external nonReentrant {
        DCAConfig storage config = dcaConfigs[msg.sender];
        
        if (!config.active) revert DCANotActive();

        uint256 refundAmount = pendingDCADeposits[msg.sender];
        
        // Clear state
        config.active = false;
        pendingDCADeposits[msg.sender] = 0;

        // Refund USDXL
        if (refundAmount > 0) {
            usdxl.safeTransfer(msg.sender, refundAmount);
        }

        emit DCACancelled(msg.sender, refundAmount);
    }

    /**
     * @notice Check if DCA is ready to execute for a user
     * @param user Address to check
     * @return ready Whether DCA is ready to execute
     */
    function isDCAReady(address user) external view returns (bool ready) {
        DCAConfig memory config = dcaConfigs[user];
        
        if (!config.active) return false;
        if (block.timestamp < config.lastExecutionTime + config.frequency) return false;
        if (pendingDCADeposits[user] < config.amountPerExecution) return false;

        // Check safety parameters
        (, , , uint256 currentLTV, , uint256 healthFactor) = hypurrPool.getUserAccountData(address(this));
        
        if (currentLTV > config.maxLTV * 1e2) return false;
        if (healthFactor < config.minHF) return false;

        return true;
    }

    /**
     * @notice Get DCA progress for a user
     * @param user Address to check
     * @return executed Amount executed so far
     * @return total Total DCA amount
     * @return percentComplete Percentage complete (in basis points)
     */
    function getDCAProgress(address user) external view returns (
        uint256 executed,
        uint256 total,
        uint256 percentComplete
    ) {
        DCAConfig memory config = dcaConfigs[user];
        executed = config.executedAmount;
        total = config.totalAmount;
        percentComplete = total > 0 ? (executed * 10000) / total : 0;
    }

    // ============ Keeper Management ============

    /**
     * @notice Add authorized keeper
     * @param keeper Address to authorize
     */
    function addKeeper(address keeper) external onlyOwner {
        keepers[keeper] = true;
        emit KeeperAdded(keeper);
    }

    /**
     * @notice Remove keeper authorization
     * @param keeper Address to remove
     */
    function removeKeeper(address keeper) external onlyOwner {
        keepers[keeper] = false;
        emit KeeperRemoved(keeper);
    }

    /**
     * @notice Check if address is authorized keeper
     * @param keeper Address to check
     * @return authorized Whether address is keeper
     */
    function isKeeper(address keeper) external view returns (bool authorized) {
        return keepers[keeper];
    }
}
