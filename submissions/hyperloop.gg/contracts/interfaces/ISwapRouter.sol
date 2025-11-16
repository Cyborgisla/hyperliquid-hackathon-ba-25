// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISwapRouter
 * @notice Interface for DEX swap functionality on HyperEVM
 * @dev Compatible with Uniswap V2/V3 style routers
 */
interface ISwapRouter {
    /**
     * @notice Swap exact tokens for tokens
     * @param amountIn Amount of input tokens
     * @param amountOutMin Minimum amount of output tokens
     * @param path Array of token addresses representing the swap path
     * @param to Recipient address
     * @param deadline Transaction deadline
     * @return amounts Array of amounts for each step in the path
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Get amounts out for a given input amount
     * @param amountIn Amount of input tokens
     * @param path Array of token addresses representing the swap path
     * @return amounts Array of output amounts for each step
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    /**
     * @notice Get amounts in for a given output amount
     * @param amountOut Desired output amount
     * @param path Array of token addresses representing the swap path
     * @return amounts Array of input amounts for each step
     */
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}
