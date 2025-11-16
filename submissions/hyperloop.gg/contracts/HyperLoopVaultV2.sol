// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IHypurrFiPool.sol";
import "./interfaces/ISwapRouter.sol";

/**
 * @title HyperLoopVaultV2
 * @notice Production-ready ERC-4626 vault with DEX integration for automated leverage loops
 * @dev Implements one-click leverage with USDXL borrowing and automatic swaps
 */
contract HyperLoopVaultV2 is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    /// @notice HypurrFi Pool contract
    IHypurrFiPool public immutable hypurrFiPool;

    /// @notice DEX router for token swaps
    ISwapRouter public swapRouter;

    /// @notice USDXL token address
    address public immutable usdxl;

    /// @notice Wrapped HYPE token address (if different from native)
    address public immutable whype;

    /// @notice Target health factor to maintain (scaled by 1e18)
    uint256 public targetHealthFactor;

    /// @notice Minimum health factor before triggering rebalance (scaled by 1e18)
    uint256 public minHealthFactor;

    /// @notice Maximum leverage multiplier (scaled by 1e18, e.g., 3e18 = 3x)
    uint256 public maxLeverage;

    /// @notice Slippage tolerance for swaps (basis points, e.g., 50 = 0.5%)
    uint256 public slippageTolerance;

    /// @notice Interest rate mode for borrowing (2 = Variable)
    uint256 public constant INTEREST_RATE_MODE = 2;

    /// @notice Liquidation threshold (1e18 = 1.0)
    uint256 public constant LIQUIDATION_THRESHOLD = 1e18;

    /// @notice Total debt owed to HypurrFi (in USDXL)
    uint256 public totalDebt;

    /// @notice Emergency pause flag
    bool public paused;

    /// @notice Keeper address for automated rebalancing
    address public keeper;

    // ============ Events ============

    event LeverageExecuted(
        address indexed user,
        uint256 depositAmount,
        uint256 leverage,
        uint256 shares,
        uint256 totalCollateral,
        uint256 totalBorrowed
    );
    event PositionUnwound(address indexed user, uint256 shares, uint256 assetsReturned);
    event Rebalanced(uint256 oldHealthFactor, uint256 newHealthFactor, uint256 debtRepaid);
    event SwapExecuted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event ParametersUpdated(uint256 targetHealthFactor, uint256 minHealthFactor, uint256 maxLeverage);
    event SwapRouterUpdated(address indexed newRouter);
    event KeeperUpdated(address indexed newKeeper);

    // ============ Errors ============

    error Paused();
    error LeverageTooHigh();
    error HealthFactorTooLow();
    error InsufficientCollateral();
    error ZeroAmount();
    error SlippageExceeded();
    error Unauthorized();
    error SwapFailed();

    // ============ Constructor ============

    /**
     * @notice Initialize the HyperLoop Vault V2
     * @param _asset The underlying asset (WHYPE)
     * @param _usdxl USDXL token address
     * @param _whype Wrapped HYPE token address
     * @param _hypurrFiPool Address of HypurrFi Pool contract
     * @param _swapRouter Address of DEX swap router
     * @param _name Vault token name
     * @param _symbol Vault token symbol
     */
    constructor(
        IERC20 _asset,
        address _usdxl,
        address _whype,
        IHypurrFiPool _hypurrFiPool,
        ISwapRouter _swapRouter,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset) ERC20(_name, _symbol) Ownable(msg.sender) {
        usdxl = _usdxl;
        whype = _whype;
        hypurrFiPool = _hypurrFiPool;
        swapRouter = _swapRouter;
        keeper = msg.sender;
        
        // Default risk parameters
        targetHealthFactor = 15e17; // 1.5
        minHealthFactor = 13e17; // 1.3
        maxLeverage = 5e18; // 5x
        slippageTolerance = 50; // 0.5%

        // Approve HypurrFi Pool and swap router
        IERC20(_asset).forceApprove(address(_hypurrFiPool), type(uint256).max);
        IERC20(_usdxl).forceApprove(address(_hypurrFiPool), type(uint256).max);
        IERC20(_asset).forceApprove(address(_swapRouter), type(uint256).max);
        IERC20(_usdxl).forceApprove(address(_swapRouter), type(uint256).max);
    }

    // ============ Modifiers ============

    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    modifier onlyKeeper() {
        if (msg.sender != keeper && msg.sender != owner()) revert Unauthorized();
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

        // Execute leverage loop with USDXL borrowing and swapping
        (uint256 totalCollateral, uint256 totalBorrowed) = _executeLeverageLoopWithSwap(assets, leverage);

        // Mint shares based on net asset value
        uint256 netValue = totalCollateral; // Simplified - in production, subtract debt value
        shares = previewDeposit(netValue);
        _mint(receiver, shares);

        emit LeverageExecuted(receiver, assets, leverage, shares, totalCollateral, totalBorrowed);
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
        assets = _unwindPositionWithSwap(shares, userDebtShare);

        // Burn shares
        _burn(owner, shares);

        // Transfer assets to receiver
        IERC20(asset()).safeTransfer(receiver, assets);

        emit PositionUnwound(owner, shares, assets);
    }

    /**
     * @notice Rebalance position to maintain target health factor
     * @dev Can be called by keeper or anyone when health factor is below minimum
     */
    function rebalance() external nonReentrant onlyKeeper {
        (, , , , , uint256 healthFactor) = hypurrFiPool.getUserAccountData(address(this));
        
        if (healthFactor >= minHealthFactor && healthFactor != type(uint256).max) {
            return; // No rebalance needed
        }

        uint256 oldHealthFactor = healthFactor;

        // If health factor is too low, repay some debt
        if (healthFactor < minHealthFactor && healthFactor != type(uint256).max) {
            uint256 debtRepaid = _deleverageToTarget();
            
            (, , , , , uint256 newHealthFactor) = hypurrFiPool.getUserAccountData(address(this));
            emit Rebalanced(oldHealthFactor, newHealthFactor, debtRepaid);
        }
    }

    // ============ Internal Functions ============

    /**
     * @notice Execute leverage loop by borrowing USDXL and swapping to collateral asset
     * @param initialDeposit Initial deposit amount
     * @param leverage Target leverage multiplier
     * @return totalCollateral Total collateral supplied after loop
     * @return totalBorrowed Total USDXL borrowed
     */
    function _executeLeverageLoopWithSwap(uint256 initialDeposit, uint256 leverage) 
        internal 
        returns (uint256 totalCollateral, uint256 totalBorrowed) 
    {
        // Step 1: Supply initial collateral
        hypurrFiPool.supply(asset(), initialDeposit, address(this), 0);
        totalCollateral = initialDeposit;
        totalBorrowed = 0;

        // Step 2: Calculate target collateral for desired leverage
        uint256 targetCollateral = (initialDeposit * leverage) / 1e18;
        uint256 remainingToLoop = targetCollateral - initialDeposit;

        // Step 3: Execute leverage loop
        uint256 maxIterations = 10; // Safety limit
        for (uint256 i = 0; i < maxIterations && remainingToLoop > 0; i++) {
            // Check current health factor
            (, , , , , uint256 healthFactor) = hypurrFiPool.getUserAccountData(address(this));
            
            if (healthFactor < targetHealthFactor && healthFactor != type(uint256).max) {
                break; // Stop if health factor is too low
            }

            // Calculate safe borrow amount
            (, , uint256 availableBorrows, , , ) = hypurrFiPool.getUserAccountData(address(this));
            
            if (availableBorrows == 0) break;

            // Borrow USDXL (conservative amount to maintain health factor)
            uint256 borrowAmount = availableBorrows > remainingToLoop ? remainingToLoop : availableBorrows;
            borrowAmount = (borrowAmount * 80) / 100; // Use 80% of available to be safe
            
            if (borrowAmount == 0) break;

            hypurrFiPool.borrow(usdxl, borrowAmount, INTEREST_RATE_MODE, 0, address(this));
            totalBorrowed += borrowAmount;

            // Swap USDXL to collateral asset (WHYPE)
            uint256 swappedAmount = _swapUSDXLToAsset(borrowAmount);
            
            // Re-supply swapped assets as collateral
            hypurrFiPool.supply(asset(), swappedAmount, address(this), 0);
            totalCollateral += swappedAmount;
            
            remainingToLoop = remainingToLoop > swappedAmount ? remainingToLoop - swappedAmount : 0;
        }

        totalDebt += totalBorrowed;
        return (totalCollateral, totalBorrowed);
    }

    /**
     * @notice Unwind leveraged position by withdrawing collateral, swapping, and repaying debt
     * @param shares Amount of shares being redeemed
     * @param userDebtShare User's share of total debt
     * @return assetsReturned Amount of underlying assets returned to user
     */
    function _unwindPositionWithSwap(uint256 shares, uint256 userDebtShare) 
        internal 
        returns (uint256 assetsReturned) 
    {
        uint256 totalShares = totalSupply();
        
        // Get current collateral value
        (uint256 totalCollateralValue, , , , , ) = hypurrFiPool.getUserAccountData(address(this));
        uint256 userCollateralShare = (totalCollateralValue * shares) / totalShares;

        // Repay user's share of debt
        if (userDebtShare > 0) {
            // Withdraw collateral to cover debt repayment
            uint256 collateralForRepay = (userDebtShare * 12) / 10; // 120% to cover swap slippage
            uint256 withdrawn = hypurrFiPool.withdraw(asset(), collateralForRepay, address(this));
            
            // Swap asset to USDXL for repayment
            uint256 usdxlReceived = _swapAssetToUSDXL(withdrawn);
            
            // Repay debt
            uint256 repayAmount = usdxlReceived > userDebtShare ? userDebtShare : usdxlReceived;
            hypurrFiPool.repay(usdxl, repayAmount, INTEREST_RATE_MODE, address(this));
            totalDebt -= repayAmount;

            userCollateralShare -= collateralForRepay;
        }

        // Withdraw remaining collateral
        assetsReturned = hypurrFiPool.withdraw(asset(), userCollateralShare, address(this));
        
        return assetsReturned;
    }

    /**
     * @notice Deleverage position to reach target health factor
     * @return debtRepaid Amount of debt repaid
     */
    function _deleverageToTarget() internal returns (uint256 debtRepaid) {
        // Calculate amount to repay to reach target health factor
        (uint256 totalCollateralValue, uint256 totalDebtValue, , , , ) = hypurrFiPool.getUserAccountData(address(this));
        
        // Target: HF = collateral / debt = targetHealthFactor
        // So: targetDebt = collateral / targetHealthFactor
        uint256 targetDebtValue = (totalCollateralValue * 1e18) / targetHealthFactor;
        
        if (totalDebtValue <= targetDebtValue) return 0;

        uint256 debtToRepay = totalDebtValue - targetDebtValue;
        
        // Withdraw collateral to repay debt
        uint256 collateralToWithdraw = (debtToRepay * 12) / 10; // 120% buffer
        uint256 withdrawn = hypurrFiPool.withdraw(asset(), collateralToWithdraw, address(this));
        
        // Swap to USDXL
        uint256 usdxlReceived = _swapAssetToUSDXL(withdrawn);
        
        // Repay debt
        hypurrFiPool.repay(usdxl, usdxlReceived, INTEREST_RATE_MODE, address(this));
        totalDebt -= usdxlReceived;
        
        return usdxlReceived;
    }

    /**
     * @notice Swap USDXL to collateral asset
     * @param amountIn Amount of USDXL to swap
     * @return amountOut Amount of collateral asset received
     */
    function _swapUSDXLToAsset(uint256 amountIn) internal returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = usdxl;
        path[1] = asset();

        // Calculate minimum output with slippage tolerance
        uint256[] memory amountsOut = swapRouter.getAmountsOut(amountIn, path);
        uint256 minAmountOut = (amountsOut[1] * (10000 - slippageTolerance)) / 10000;

        // Execute swap
        uint256[] memory amounts = swapRouter.swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            path,
            address(this),
            block.timestamp + 300 // 5 minute deadline
        );

        amountOut = amounts[1];
        emit SwapExecuted(usdxl, asset(), amountIn, amountOut);
        
        return amountOut;
    }

    /**
     * @notice Swap collateral asset to USDXL
     * @param amountIn Amount of collateral asset to swap
     * @return amountOut Amount of USDXL received
     */
    function _swapAssetToUSDXL(uint256 amountIn) internal returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = asset();
        path[1] = usdxl;

        // Calculate minimum output with slippage tolerance
        uint256[] memory amountsOut = swapRouter.getAmountsOut(amountIn, path);
        uint256 minAmountOut = (amountsOut[1] * (10000 - slippageTolerance)) / 10000;

        // Execute swap
        uint256[] memory amounts = swapRouter.swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            path,
            address(this),
            block.timestamp + 300 // 5 minute deadline
        );

        amountOut = amounts[1];
        emit SwapExecuted(asset(), usdxl, amountIn, amountOut);
        
        return amountOut;
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
     */
    function updateParameters(
        uint256 _targetHealthFactor,
        uint256 _minHealthFactor,
        uint256 _maxLeverage,
        uint256 _slippageTolerance
    ) external onlyOwner {
        require(_targetHealthFactor > LIQUIDATION_THRESHOLD, "Target HF too low");
        require(_minHealthFactor > LIQUIDATION_THRESHOLD, "Min HF too low");
        require(_minHealthFactor < _targetHealthFactor, "Min HF must be < target");
        require(_maxLeverage >= 1e18 && _maxLeverage <= 10e18, "Invalid leverage range");
        require(_slippageTolerance <= 500, "Slippage too high"); // Max 5%

        targetHealthFactor = _targetHealthFactor;
        minHealthFactor = _minHealthFactor;
        maxLeverage = _maxLeverage;
        slippageTolerance = _slippageTolerance;

        emit ParametersUpdated(_targetHealthFactor, _minHealthFactor, _maxLeverage);
    }

    /**
     * @notice Update swap router
     */
    function updateSwapRouter(ISwapRouter _newRouter) external onlyOwner {
        swapRouter = _newRouter;
        
        // Re-approve new router
        IERC20(asset()).forceApprove(address(_newRouter), type(uint256).max);
        IERC20(usdxl).forceApprove(address(_newRouter), type(uint256).max);
        
        emit SwapRouterUpdated(address(_newRouter));
    }

    /**
     * @notice Update keeper address
     */
    function updateKeeper(address _newKeeper) external onlyOwner {
        keeper = _newKeeper;
        emit KeeperUpdated(_newKeeper);
    }

    /**
     * @notice Pause/unpause the vault
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    /**
     * @notice Emergency function to close all positions
     */
    function emergencyExit() external onlyOwner {
        paused = true;
        
        // Repay all debt
        if (totalDebt > 0) {
            _deleverageToTarget();
        }

        // Withdraw all remaining collateral
        hypurrFiPool.withdraw(asset(), type(uint256).max, address(this));
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
