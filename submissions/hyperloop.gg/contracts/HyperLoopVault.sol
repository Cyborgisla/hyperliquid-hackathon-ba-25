// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IHypurrFiPool.sol";

/**
 * @title HyperLoopVault
 * @notice ERC-4626 compliant vault that automates leveraged lending loops on HypurrFi
 * @dev Implements one-click leverage with intelligent risk management
 */
contract HyperLoopVault is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    /// @notice HypurrFi Pool contract
    IHypurrFiPool public immutable hypurrFiPool;

    /// @notice Asset to borrow for leverage (e.g., USDXL)
    IERC20 public immutable borrowAsset;

    /// @notice Target health factor to maintain (scaled by 1e18)
    uint256 public targetHealthFactor;

    /// @notice Minimum health factor before triggering rebalance (scaled by 1e18)
    uint256 public minHealthFactor;

    /// @notice Maximum leverage multiplier (scaled by 1e18, e.g., 3e18 = 3x)
    uint256 public maxLeverage;

    /// @notice Interest rate mode for borrowing (2 = Variable)
    uint256 public constant INTEREST_RATE_MODE = 2;

    /// @notice Liquidation threshold (1e18 = 1.0)
    uint256 public constant LIQUIDATION_THRESHOLD = 1e18;

    /// @notice Total debt owed to HypurrFi (in borrow asset)
    uint256 public totalDebt;

    /// @notice Emergency pause flag
    bool public paused;

    // ============ Events ============

    event LeverageExecuted(address indexed user, uint256 depositAmount, uint256 leverage, uint256 shares);
    event PositionUnwound(address indexed user, uint256 shares, uint256 assetsReturned);
    event Rebalanced(uint256 oldHealthFactor, uint256 newHealthFactor);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event ParametersUpdated(uint256 targetHealthFactor, uint256 minHealthFactor, uint256 maxLeverage);

    // ============ Errors ============

    error Paused();
    error LeverageTooHigh();
    error HealthFactorTooLow();
    error InsufficientCollateral();
    error ZeroAmount();

    // ============ Constructor ============

    /**
     * @notice Initialize the HyperLoop Vault
     * @param _asset The underlying asset (e.g., HYPE)
     * @param _borrowAsset The asset to borrow for leverage (e.g., USDXL)
     * @param _hypurrFiPool Address of HypurrFi Pool contract
     * @param _name Vault token name
     * @param _symbol Vault token symbol
     */
    constructor(
        IERC20 _asset,
        IERC20 _borrowAsset,
        IHypurrFiPool _hypurrFiPool,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) Ownable(msg.sender) {
        borrowAsset = _borrowAsset;
        hypurrFiPool = _hypurrFiPool;
        
        // Default risk parameters
        targetHealthFactor = 15e17; // 1.5
        minHealthFactor = 13e17; // 1.3
        maxLeverage = 5e18; // 5x

        // Approve HypurrFi Pool to spend assets
        IERC20(_asset).forceApprove(address(_hypurrFiPool), type(uint256).max);
        _borrowAsset.forceApprove(address(_hypurrFiPool), type(uint256).max);
    }

    // ============ Modifiers ============

    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    // ============ Main Functions ============

    /**
     * @notice Deposit assets and open leveraged position
     * @param assets Amount of underlying asset to deposit
     * @param receiver Address to receive vault shares
     * @param leverage Desired leverage multiplier (scaled by 1e18)
     * @return shares Amount of vault shares minted
     */
    function depositWithLeverage(
        uint256 assets,
        address receiver,
        uint256 leverage
    ) external nonReentrant whenNotPaused returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();
        if (leverage > maxLeverage) revert LeverageTooHigh();
        if (leverage < 1e18) leverage = 1e18; // Minimum 1x (no leverage)

        // Transfer assets from user
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

        // Execute leverage loop
        uint256 totalCollateral = _executeLeverageLoop(assets, leverage);

        // Mint shares based on total collateral value
        shares = previewDeposit(totalCollateral);
        _mint(receiver, shares);

        emit LeverageExecuted(receiver, assets, leverage, shares);
    }

    /**
     * @notice Withdraw assets and unwind leveraged position
     * @param shares Amount of vault shares to redeem
     * @param receiver Address to receive underlying assets
     * @param owner Owner of the shares
     * @return assets Amount of underlying assets returned
     */
    function redeemWithUnwind(
        uint256 shares,
        address receiver,
        address owner
    ) external nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();
        
        // Check allowance if not owner
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // Calculate user's share of total position
        uint256 totalShares = totalSupply();
        uint256 userDebtShare = (totalDebt * shares) / totalShares;

        // Unwind position: repay debt and withdraw collateral
        assets = _unwindPosition(shares, userDebtShare);

        // Burn shares
        _burn(owner, shares);

        // Transfer assets to receiver
        IERC20(asset()).safeTransfer(receiver, assets);

        emit PositionUnwound(owner, shares, assets);
    }

    /**
     * @notice Rebalance position to maintain target health factor
     * @dev Can be called by anyone when health factor is below minimum
     */
    function rebalance() external nonReentrant {
        (, , , , , uint256 healthFactor) = hypurrFiPool.getUserAccountData(address(this));
        
        if (healthFactor >= minHealthFactor && healthFactor != type(uint256).max) {
            return; // No rebalance needed
        }

        uint256 oldHealthFactor = healthFactor;

        // If health factor is too low, repay some debt
        if (healthFactor < minHealthFactor && healthFactor != type(uint256).max) {
            _deleverageToTarget();
        }

        (, , , , , uint256 newHealthFactor) = hypurrFiPool.getUserAccountData(address(this));
        
        emit Rebalanced(oldHealthFactor, newHealthFactor);
    }

    /**
     * @notice Emergency function to close all positions and return assets to users
     * @dev Only callable by owner
     */
    function emergencyExit() external onlyOwner {
        paused = true;
        
        // Repay all debt
        if (totalDebt > 0) {
            uint256 debtToRepay = totalDebt;
            
            // Withdraw enough collateral to repay debt
            uint256 collateralToWithdraw = (debtToRepay * 12) / 10; // 120% to be safe
            hypurrFiPool.withdraw(asset(), collateralToWithdraw, address(this));
            
            // Swap collateral for borrow asset if needed (simplified - would use DEX in production)
            // For now, assume we can repay directly
            
            hypurrFiPool.repay(address(borrowAsset), debtToRepay, INTEREST_RATE_MODE, address(this));
            totalDebt = 0;
        }

        // Withdraw all remaining collateral
        hypurrFiPool.withdraw(asset(), type(uint256).max, address(this));
    }

    // ============ Internal Functions ============

    /**
     * @notice Execute leverage loop by repeatedly borrowing and re-supplying
     * @param initialDeposit Initial deposit amount
     * @param leverage Target leverage multiplier
     * @return totalCollateral Total collateral supplied after loop
     */
    function _executeLeverageLoop(uint256 initialDeposit, uint256 leverage) internal returns (uint256 totalCollateral) {
        // Step 1: Supply initial collateral
        hypurrFiPool.supply(asset(), initialDeposit, address(this), 0);
        totalCollateral = initialDeposit;

        // Step 2: Calculate total collateral needed for target leverage
        uint256 targetCollateral = (initialDeposit * leverage) / 1e18;
        uint256 remainingToLoop = targetCollateral - initialDeposit;

        // Step 3: Execute loop
        while (remainingToLoop > 0 && totalCollateral < targetCollateral) {
            // Check current health factor
            (, , , , , uint256 healthFactor) = hypurrFiPool.getUserAccountData(address(this));
            
            if (healthFactor < targetHealthFactor && healthFactor != type(uint256).max) {
                break; // Stop if health factor is too low
            }

            // Calculate safe borrow amount (conservative)
            (, , uint256 availableBorrows, , , ) = hypurrFiPool.getUserAccountData(address(this));
            uint256 borrowAmount = availableBorrows > remainingToLoop ? remainingToLoop : availableBorrows;
            
            if (borrowAmount == 0) break;

            // Borrow
            hypurrFiPool.borrow(address(borrowAsset), borrowAmount, INTEREST_RATE_MODE, 0, address(this));
            totalDebt += borrowAmount;

            // In production, would swap borrowAsset for asset here via DEX
            // For simplicity, assuming borrowAsset == asset or 1:1 swap
            
            // Re-supply borrowed amount as collateral
            hypurrFiPool.supply(asset(), borrowAmount, address(this), 0);
            totalCollateral += borrowAmount;
            remainingToLoop -= borrowAmount;
        }

        return totalCollateral;
    }

    /**
     * @notice Unwind leveraged position by repaying debt and withdrawing collateral
     * @param shares Amount of shares being redeemed
     * @param userDebtShare User's share of total debt
     * @return assetsReturned Amount of underlying assets returned to user
     */
    function _unwindPosition(uint256 shares, uint256 userDebtShare) internal returns (uint256 assetsReturned) {
        uint256 totalShares = totalSupply();
        
        // Get current collateral value
        (uint256 totalCollateralValue, , , , , ) = hypurrFiPool.getUserAccountData(address(this));
        uint256 userCollateralShare = (totalCollateralValue * shares) / totalShares;

        // Repay user's share of debt
        if (userDebtShare > 0) {
            // Withdraw enough collateral to repay debt
            uint256 collateralForRepay = (userDebtShare * 11) / 10; // 110% to cover any interest
            hypurrFiPool.withdraw(asset(), collateralForRepay, address(this));
            
            // Repay debt
            hypurrFiPool.repay(address(borrowAsset), userDebtShare, INTEREST_RATE_MODE, address(this));
            totalDebt -= userDebtShare;

            userCollateralShare -= collateralForRepay;
        }

        // Withdraw remaining collateral
        assetsReturned = hypurrFiPool.withdraw(asset(), userCollateralShare, address(this));
        
        return assetsReturned;
    }

    /**
     * @notice Deleverage position to reach target health factor
     */
    function _deleverageToTarget() internal {
        // Calculate amount to repay to reach target health factor
        (uint256 totalCollateralValue, uint256 totalDebtValue, , , , ) = hypurrFiPool.getUserAccountData(address(this));
        
        // Target: HF = collateral / debt = targetHealthFactor
        // So: targetDebt = collateral / targetHealthFactor
        uint256 targetDebtValue = (totalCollateralValue * 1e18) / targetHealthFactor;
        
        if (totalDebtValue <= targetDebtValue) return;

        uint256 debtToRepay = totalDebtValue - targetDebtValue;
        
        // Withdraw collateral to repay debt
        uint256 collateralToWithdraw = (debtToRepay * 11) / 10; // 110% buffer
        hypurrFiPool.withdraw(asset(), collateralToWithdraw, address(this));
        
        // Repay debt
        hypurrFiPool.repay(address(borrowAsset), debtToRepay, INTEREST_RATE_MODE, address(this));
        totalDebt -= debtToRepay;
    }

    // ============ View Functions ============

    /**
     * @notice Get current health factor of the vault
     */
    function getHealthFactor() external view returns (uint256) {
        (, , , , , uint256 healthFactor) = hypurrFiPool.getUserAccountData(address(this));
        return healthFactor;
    }

    /**
     * @notice Get current leverage ratio
     */
    function getCurrentLeverage() external view returns (uint256) {
        (uint256 totalCollateralValue, uint256 totalDebtValue, , , , ) = hypurrFiPool.getUserAccountData(address(this));
        
        if (totalCollateralValue == 0) return 1e18;
        if (totalDebtValue == 0) return 1e18;
        
        return (totalCollateralValue * 1e18) / (totalCollateralValue - totalDebtValue);
    }

    /**
     * @notice Calculate total assets under management
     */
    function totalAssets() public view override returns (uint256) {
        (uint256 totalCollateralValue, uint256 totalDebtValue, , , , ) = hypurrFiPool.getUserAccountData(address(this));
        
        // Net asset value = collateral - debt
        return totalCollateralValue > totalDebtValue ? totalCollateralValue - totalDebtValue : 0;
    }

    // ============ Admin Functions ============

    /**
     * @notice Update risk parameters
     * @param _targetHealthFactor New target health factor
     * @param _minHealthFactor New minimum health factor
     * @param _maxLeverage New maximum leverage
     */
    function updateParameters(
        uint256 _targetHealthFactor,
        uint256 _minHealthFactor,
        uint256 _maxLeverage
    ) external onlyOwner {
        require(_targetHealthFactor > LIQUIDATION_THRESHOLD, "Target HF too low");
        require(_minHealthFactor > LIQUIDATION_THRESHOLD, "Min HF too low");
        require(_minHealthFactor < _targetHealthFactor, "Min HF must be < target");
        require(_maxLeverage >= 1e18 && _maxLeverage <= 10e18, "Invalid leverage range");

        targetHealthFactor = _targetHealthFactor;
        minHealthFactor = _minHealthFactor;
        maxLeverage = _maxLeverage;

        emit ParametersUpdated(_targetHealthFactor, _minHealthFactor, _maxLeverage);
    }

    /**
     * @notice Pause/unpause the vault
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    /**
     * @notice Override deposit to use depositWithLeverage
     */
    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        return depositWithLeverage(assets, receiver, 1e18); // Default 1x (no leverage)
    }

    /**
     * @notice Override redeem to use redeemWithUnwind
     */
    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        return redeemWithUnwind(shares, receiver, owner);
    }
}
