// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IHypurrFiPool.sol";
import "./interfaces/ISwapRouter.sol";

/**
 * @title HypurrAutoLoopVault
 * @notice ERC-4626 compliant vault that automates leveraged HYPE/stHYPE loops on HypurrFi
 * @dev Implements one-click leverage loops with built-in health factor guardrails
 * 
 * Key Features:
 * - ERC-4626 compliant (deposit/mint/withdraw/redeem)
 * - Automated leverage loops (supply → borrow USDXL → swap → re-supply)
 * - Health factor monitoring and auto-rebalancing
 * - Configurable target leverage and safety buffers
 */
contract HypurrAutoLoopVault is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    /// @notice The underlying asset (WHYPE or stHYPE)
    IERC20 public immutable asset;
    
    /// @notice HypurrFi lending pool
    IHypurrFiPool public immutable hypurrPool;
    
    /// @notice USDXL token (borrowed asset)
    IERC20 public immutable usdxl;
    
    /// @notice DEX router for swaps
    ISwapRouter public immutable swapRouter;

    /// @notice Target leverage multiplier (in basis points, e.g., 30000 = 3.0x)
    uint256 public targetLeverage = 30000; // 3.0x default
    
    /// @notice Minimum health factor to maintain (in 18 decimals, e.g., 1.5e18 = 1.5)
    uint256 public minHealthFactor = 1_500_000_000_000_000_000; // 1.5
    
    /// @notice Health factor threshold to trigger rebalance (in 18 decimals)
    uint256 public rebalanceThreshold = 1_300_000_000_000_000_000; // 1.3
    
    /// @notice Maximum number of loop iterations
    uint256 public maxLoopIterations = 5;
    
    /// @notice Slippage tolerance for swaps (in basis points, e.g., 50 = 0.5%)
    uint256 public slippageTolerance = 50; // 0.5%

    /// @notice Fee charged on profits (in basis points, e.g., 1000 = 10%)
    uint256 public performanceFee = 1000; // 10%
    
    /// @notice Treasury address for fees
    address public treasury;

    /// @notice Paused state for emergency
    bool public paused;

    // ============ Events ============

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
    event LeverageLoopExecuted(uint256 iterations, uint256 finalCollateral, uint256 finalDebt);
    event Rebalanced(uint256 newHealthFactor, uint256 collateralWithdrawn, uint256 debtRepaid);
    event ParametersUpdated(uint256 targetLeverage, uint256 minHealthFactor, uint256 rebalanceThreshold);
    event EmergencyPaused(address indexed caller);
    event EmergencyUnpaused(address indexed caller);

    // ============ Errors ============

    error VaultPaused();
    error ZeroAmount();
    error InsufficientShares();
    error HealthFactorTooLow();
    error SlippageExceeded();
    error InvalidParameter();

    // ============ Constructor ============

    constructor(
        address _asset,
        address _hypurrPool,
        address _usdxl,
        address _swapRouter,
        address _treasury,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        asset = IERC20(_asset);
        hypurrPool = IHypurrFiPool(_hypurrPool);
        usdxl = IERC20(_usdxl);
        swapRouter = ISwapRouter(_swapRouter);
        treasury = _treasury;

        // Approve HypurrFi pool for asset and USDXL
        asset.approve(_hypurrPool, type(uint256).max);
        usdxl.approve(_hypurrPool, type(uint256).max);
        
        // Approve swap router for USDXL
        usdxl.approve(_swapRouter, type(uint256).max);
    }

    // ============ Modifiers ============

    modifier whenNotPaused() {
        if (paused) revert VaultPaused();
        _;
    }

    // ============ ERC-4626 Core Functions ============

    /**
     * @notice Deposit assets and receive shares
     * @param assets Amount of underlying asset to deposit
     * @param receiver Address to receive shares
     * @return shares Amount of shares minted
     */
    function deposit(uint256 assets, address receiver) public nonReentrant whenNotPaused returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();

        // Calculate shares to mint
        shares = convertToShares(assets);

        // Transfer assets from caller
        asset.safeTransferFrom(msg.sender, address(this), assets);

        // Mint shares to receiver
        _mint(receiver, shares);

        // Execute leverage loop
        _executeLeverageLoop(assets);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Mint exact shares by depositing assets
     * @param shares Amount of shares to mint
     * @param receiver Address to receive shares
     * @return assets Amount of assets deposited
     */
    function mint(uint256 shares, address receiver) public nonReentrant whenNotPaused returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();

        // Calculate assets needed
        assets = convertToAssets(shares);

        // Transfer assets from caller
        asset.safeTransferFrom(msg.sender, address(this), assets);

        // Mint shares to receiver
        _mint(receiver, shares);

        // Execute leverage loop
        _executeLeverageLoop(assets);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Withdraw assets by burning shares
     * @param assets Amount of assets to withdraw
     * @param receiver Address to receive assets
     * @param owner Address that owns the shares
     * @return shares Amount of shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner) public nonReentrant returns (uint256 shares) {
        if (assets == 0) revert ZeroAmount();

        // Calculate shares to burn
        shares = convertToShares(assets);

        // Check allowance if caller is not owner
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // Unwind position to get assets
        _unwindPosition(assets);

        // Burn shares
        _burn(owner, shares);

        // Transfer assets to receiver
        asset.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @notice Redeem shares for assets
     * @param shares Amount of shares to redeem
     * @param receiver Address to receive assets
     * @param owner Address that owns the shares
     * @return assets Amount of assets withdrawn
     */
    function redeem(uint256 shares, address receiver, address owner) public nonReentrant returns (uint256 assets) {
        if (shares == 0) revert ZeroAmount();

        // Check allowance if caller is not owner
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        // Calculate assets to withdraw
        assets = convertToAssets(shares);

        // Unwind position to get assets
        _unwindPosition(assets);

        // Burn shares
        _burn(owner, shares);

        // Transfer assets to receiver
        asset.safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    // ============ ERC-4626 View Functions ============

    /**
     * @notice Total assets under management (including leveraged position)
     * @return Total value of assets in the vault
     */
    function totalAssets() public view returns (uint256) {
        (
            uint256 totalCollateral,
            uint256 totalDebt,
            ,,,
        ) = hypurrPool.getUserAccountData(address(this));

        // Convert from USD (8 decimals) to asset decimals (18)
        // Total assets = collateral - debt (in asset terms)
        // This is simplified - in production, use oracle prices
        uint256 collateralInAssets = totalCollateral * 1e10; // USD to 18 decimals
        uint256 debtInAssets = totalDebt * 1e10;

        if (collateralInAssets > debtInAssets) {
            return collateralInAssets - debtInAssets;
        }
        return 0;
    }

    /**
     * @notice Convert assets to shares
     * @param assets Amount of assets
     * @return shares Equivalent amount of shares
     */
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return assets; // 1:1 for first deposit
        }
        return (assets * supply) / totalAssets();
    }

    /**
     * @notice Convert shares to assets
     * @param shares Amount of shares
     * @return assets Equivalent amount of assets
     */
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return shares;
        }
        return (shares * totalAssets()) / supply;
    }

    /**
     * @notice Maximum amount that can be deposited
     * @return Maximum deposit amount
     */
    function maxDeposit(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Maximum shares that can be minted
     * @return Maximum mint amount
     */
    function maxMint(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @notice Maximum amount that can be withdrawn
     * @param owner Address of share owner
     * @return Maximum withdrawal amount
     */
    function maxWithdraw(address owner) public view returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    /**
     * @notice Maximum shares that can be redeemed
     * @param owner Address of share owner
     * @return Maximum redeem amount
     */
    function maxRedeem(address owner) public view returns (uint256) {
        return balanceOf(owner);
    }

    /**
     * @notice Preview deposit to get shares
     * @param assets Amount to deposit
     * @return shares Shares that would be minted
     */
    function previewDeposit(uint256 assets) public view returns (uint256 shares) {
        return convertToShares(assets);
    }

    /**
     * @notice Preview mint to get assets needed
     * @param shares Shares to mint
     * @return assets Assets that would be needed
     */
    function previewMint(uint256 shares) public view returns (uint256 assets) {
        return convertToAssets(shares);
    }

    /**
     * @notice Preview withdraw to get shares burned
     * @param assets Amount to withdraw
     * @return shares Shares that would be burned
     */
    function previewWithdraw(uint256 assets) public view returns (uint256 shares) {
        return convertToShares(assets);
    }

    /**
     * @notice Preview redeem to get assets received
     * @param shares Shares to redeem
     * @return assets Assets that would be received
     */
    function previewRedeem(uint256 shares) public view returns (uint256 assets) {
        return convertToAssets(shares);
    }

    // ============ Leverage Loop Functions ============

    /**
     * @notice Execute automated leverage loop
     * @param initialAmount Initial amount of assets to loop
     */
    function _executeLeverageLoop(uint256 initialAmount) internal {
        uint256 currentAmount = initialAmount;
        uint256 totalCollateral = initialAmount;
        uint256 totalDebt = 0;

        // Supply initial collateral
        hypurrPool.supply(address(asset), currentAmount, address(this), 0);

        // Execute loop iterations
        for (uint256 i = 0; i < maxLoopIterations; i++) {
            // Calculate how much to borrow based on target leverage
            uint256 borrowAmount = _calculateBorrowAmount(totalCollateral, totalDebt);
            
            if (borrowAmount == 0) break;

            // Borrow USDXL
            hypurrPool.borrow(address(usdxl), borrowAmount, 2, 0, address(this)); // 2 = variable rate
            totalDebt += borrowAmount;

            // Swap USDXL to asset
            uint256 swappedAmount = _swapUSDXLToAsset(borrowAmount);
            
            // Supply swapped assets back as collateral
            hypurrPool.supply(address(asset), swappedAmount, address(this), 0);
            totalCollateral += swappedAmount;
            currentAmount = swappedAmount;

            // Check health factor
            (, , , , , uint256 healthFactor) = hypurrPool.getUserAccountData(address(this));
            if (healthFactor < minHealthFactor) {
                revert HealthFactorTooLow();
            }

            // Stop if we've reached target leverage
            if (totalCollateral * 10000 / (totalCollateral - totalDebt) >= targetLeverage) {
                break;
            }
        }

        emit LeverageLoopExecuted(maxLoopIterations, totalCollateral, totalDebt);
    }

    /**
     * @notice Calculate optimal borrow amount for next iteration
     * @param totalCollateral Current total collateral
     * @param totalDebt Current total debt
     * @return borrowAmount Amount to borrow
     */
    function _calculateBorrowAmount(uint256 totalCollateral, uint256 totalDebt) internal view returns (uint256) {
        // Target: (collateral / (collateral - debt)) = targetLeverage
        // Solve for additional debt needed
        
        uint256 targetDebt = (totalCollateral * (targetLeverage - 10000)) / targetLeverage;
        
        if (targetDebt <= totalDebt) return 0;
        
        uint256 additionalDebt = targetDebt - totalDebt;
        
        // Apply safety margin (90% of calculated amount)
        return (additionalDebt * 9000) / 10000;
    }

    /**
     * @notice Swap USDXL to underlying asset via DEX
     * @param usdxlAmount Amount of USDXL to swap
     * @return assetAmount Amount of asset received
     */
    function _swapUSDXLToAsset(uint256 usdxlAmount) internal returns (uint256 assetAmount) {
        // Calculate minimum output with slippage tolerance
        uint256 minOutput = (usdxlAmount * (10000 - slippageTolerance)) / 10000;

        // Execute swap via router
        address[] memory path = new address[](2);
        path[0] = address(usdxl);
        path[1] = address(asset);

        uint256[] memory amounts = swapRouter.swapExactTokensForTokens(
            usdxlAmount,
            minOutput,
            path,
            address(this),
            block.timestamp + 300 // 5 minute deadline
        );

        assetAmount = amounts[1];
    }

    /**
     * @notice Unwind leveraged position to withdraw assets
     * @param assetsNeeded Amount of assets needed
     */
    function _unwindPosition(uint256 assetsNeeded) internal {
        // Get current position
        (uint256 totalCollateral, uint256 totalDebt, , , , ) = hypurrPool.getUserAccountData(address(this));

        if (totalDebt == 0) {
            // No debt, just withdraw collateral
            hypurrPool.withdraw(address(asset), assetsNeeded, address(this));
            return;
        }

        // Calculate proportion to unwind
        uint256 collateralToWithdraw = assetsNeeded;
        uint256 debtToRepay = (totalDebt * collateralToWithdraw) / totalCollateral;

        // Withdraw some collateral
        hypurrPool.withdraw(address(asset), collateralToWithdraw, address(this));

        // Swap asset to USDXL to repay debt
        uint256 usdxlReceived = _swapAssetToUSDXL(collateralToWithdraw / 2); // Use half for repayment

        // Repay debt
        if (usdxlReceived > 0) {
            hypurrPool.repay(address(usdxl), usdxlReceived, 2, address(this));
        }
    }

    /**
     * @notice Swap asset to USDXL
     * @param assetAmount Amount of asset to swap
     * @return usdxlAmount Amount of USDXL received
     */
    function _swapAssetToUSDXL(uint256 assetAmount) internal returns (uint256 usdxlAmount) {
        uint256 minOutput = (assetAmount * (10000 - slippageTolerance)) / 10000;

        address[] memory path = new address[](2);
        path[0] = address(asset);
        path[1] = address(usdxl);

        uint256[] memory amounts = swapRouter.swapExactTokensForTokens(
            assetAmount,
            minOutput,
            path,
            address(this),
            block.timestamp + 300
        );

        usdxlAmount = amounts[1];
    }

    // ============ Rebalancing Functions ============

    /**
     * @notice Rebalance position to maintain health factor
     * @dev Can be called by anyone (keeper bot)
     */
    function rebalance() external nonReentrant {
        (, , , , , uint256 healthFactor) = hypurrPool.getUserAccountData(address(this));

        if (healthFactor >= minHealthFactor) {
            return; // No rebalance needed
        }

        // Calculate how much debt to repay
        (uint256 totalCollateral, uint256 totalDebt, , , , ) = hypurrPool.getUserAccountData(address(this));
        
        // Target: bring HF back to minHealthFactor
        uint256 targetDebt = (totalCollateral * 10000) / (minHealthFactor / 1e14); // Simplified
        uint256 debtToRepay = totalDebt > targetDebt ? totalDebt - targetDebt : 0;

        if (debtToRepay > 0) {
            // Withdraw collateral
            uint256 collateralToWithdraw = (debtToRepay * 11) / 10; // 110% to account for price impact
            hypurrPool.withdraw(address(asset), collateralToWithdraw, address(this));

            // Swap to USDXL
            uint256 usdxlReceived = _swapAssetToUSDXL(collateralToWithdraw);

            // Repay debt
            hypurrPool.repay(address(usdxl), usdxlReceived, 2, address(this));

            emit Rebalanced(healthFactor, collateralToWithdraw, usdxlReceived);
        }
    }

    // ============ Admin Functions ============

    /**
     * @notice Update vault parameters
     * @param _targetLeverage New target leverage (in basis points)
     * @param _minHealthFactor New minimum health factor (in 18 decimals)
     * @param _rebalanceThreshold New rebalance threshold (in 18 decimals)
     */
    function updateParameters(
        uint256 _targetLeverage,
        uint256 _minHealthFactor,
        uint256 _rebalanceThreshold
    ) external onlyOwner {
        if (_targetLeverage < 10000 || _targetLeverage > 50000) revert InvalidParameter();
        if (_minHealthFactor < 1e18 || _minHealthFactor > 3e18) revert InvalidParameter();
        if (_rebalanceThreshold < 1e18) revert InvalidParameter();

        targetLeverage = _targetLeverage;
        minHealthFactor = _minHealthFactor;
        rebalanceThreshold = _rebalanceThreshold;

        emit ParametersUpdated(_targetLeverage, _minHealthFactor, _rebalanceThreshold);
    }

    /**
     * @notice Pause vault in emergency
     */
    function pause() external onlyOwner {
        paused = true;
        emit EmergencyPaused(msg.sender);
    }

    /**
     * @notice Unpause vault
     */
    function unpause() external onlyOwner {
        paused = false;
        emit EmergencyUnpaused(msg.sender);
    }

    /**
     * @notice Update treasury address
     * @param _treasury New treasury address
     */
    function updateTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    /**
     * @notice Get current health factor
     * @return healthFactor Current health factor (18 decimals)
     */
    function getHealthFactor() external view returns (uint256 healthFactor) {
        (, , , , , healthFactor) = hypurrPool.getUserAccountData(address(this));
    }

    /**
     * @notice Get current leverage ratio
     * @return leverage Current leverage (in basis points)
     */
    function getCurrentLeverage() external view returns (uint256 leverage) {
        (uint256 totalCollateral, uint256 totalDebt, , , , ) = hypurrPool.getUserAccountData(address(this));
        
        if (totalCollateral == 0 || totalCollateral <= totalDebt) return 10000; // 1.0x
        
        leverage = (totalCollateral * 10000) / (totalCollateral - totalDebt);
    }
}
